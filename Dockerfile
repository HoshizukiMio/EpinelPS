# syntax=docker/dockerfile:1

ARG DOTNET_VERSION=10.0-noble

FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION} AS build
ARG TARGETARCH
ARG BUILD_CONFIGURATION=Release
ARG SOURCE_REVISION
WORKDIR /src

COPY Directory.Build.props ./
COPY EpinelPS/EpinelPS.csproj EpinelPS/
COPY EpinelPS.Analyzers/EpinelPS.Analyzers.csproj EpinelPS.Analyzers/

# Restore only the server and its source generator; the desktop selector is not needed.
RUN dotnet restore EpinelPS/EpinelPS.csproj \
    -a "$TARGETARCH" \
    -p:SelfContained=false \
    -p:PublishSingleFile=false \
    -p:UseAppHost=false

COPY EpinelPS/ EpinelPS/
COPY EpinelPS.Analyzers/ EpinelPS.Analyzers/
RUN dotnet publish EpinelPS/EpinelPS.csproj \
    -c "$BUILD_CONFIGURATION" \
    -a "$TARGETARCH" \
    --no-restore \
    --self-contained false \
    -p:PublishSingleFile=false \
    -p:UseAppHost=false \
    -p:SourceRevisionId="$SOURCE_REVISION" \
    -o /out \
    && test -s /out/EpinelPS.dll \
    && test -s /out/site.pfx \
    && test -s /out/gameconfig.json \
    && test -s /out/gameversion.json \
    && test -s /out/libsodium.so \
    && test -s /out/libe_sqlite3.so \
    && test -d /out/wwwroot

FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION} AS runtime
WORKDIR /app

# ASodium's native libsodium.so is included by the architecture-specific publish.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

ENV EpinelPS__HttpPort=8080 \
    EpinelPS__HttpsPort=8443 \
    ConnectionStrings__EpinelPSConnection="Data Source=/data/epinelps.db" \
    ConnectionStrings__EpinelPSConnectionType=sqlite

COPY --from=build /out/ ./
COPY LICENSE ./LICENSE
COPY EpinelPS/log4net.config ./log4net.config
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/epinelps-entrypoint

# Keep application binaries in the image and writable state in a separate volume.
RUN mkdir -p /opt/epinelps-defaults /data/cache /data/logs /data/keys /home/app/.aspnet \
    && for file in gameconfig.json gameversion.json site.pfx; do \
        mv "/app/$file" "/opt/epinelps-defaults/$file"; \
        ln -s "/data/$file" "/app/$file"; \
    done \
    && ln -s /data/db.json /app/db.json \
    && ln -s /data/cache /app/cache \
    && ln -s /data/logs /app/logs \
    && ln -s /data/keys /home/app/.aspnet/DataProtection-Keys \
    && chown -R app:app /data /home/app/.aspnet

USER $APP_UID
VOLUME ["/data"]
EXPOSE 8080 8443

HEALTHCHECK --interval=30s --timeout=5s --start-period=5m --retries=3 \
    CMD curl --fail --silent --show-error "http://127.0.0.1:${EpinelPS__HttpPort}/" > /dev/null || exit 1

ENTRYPOINT ["epinelps-entrypoint"]
