#!/bin/sh
set -eu

if [ ! -s /app/gamecommon.json ] || [ ! -f /app/gamecommon.json ]; then
    printf '%s\n' \
        'EpinelPS: mount your gamecommon.json at /app/gamecommon.json (read-only).' \
        'Example: --mount type=bind,source=/absolute/path/gamecommon.json,target=/app/gamecommon.json,readonly' >&2
    exit 1
fi

mkdir -p /data/cache /data/logs /data/keys
for file in gameconfig.json gameversion.json site.pfx; do
    if [ ! -e "/data/$file" ]; then
        cp "/opt/epinelps-defaults/$file" "/data/$file"
    fi
done

# exec lets ASP.NET Core receive SIGTERM directly when the container is stopped.
exec dotnet /app/EpinelPS.dll --headless "$@"
