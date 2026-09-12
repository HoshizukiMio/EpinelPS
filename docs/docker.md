# Docker 构建与运行

镜像只包含 EpinelPS 服务端，使用 .NET 10 多阶段构建，支持 `linux/amd64` 和
`linux/arm64`。ServerSelector / Launcher 仍在客户端运行。

`gamecommon.json` 必须由用户自行提供，并以只读方式映射到
`/app/gamecommon.json`。构建镜像和 GitHub Actions 不需要该文件；它被
`.dockerignore` 排除，不会进入镜像或构建缓存。镜像沿用仓库自带的
`site.pfx`，客户端仍需按项目原有方式配置域名解析和信任证书。

## 本地构建

在仓库根目录执行，需要已启动的 Docker Engine / Docker Desktop：

```sh
sh scripts/docker-build.sh
```

默认镜像名为 `epinelps:latest`，默认架构为 Docker 当前使用的 Linux 架构。
可以指定镜像名、平台和其他 `docker build` 参数：

```sh
IMAGE_NAME=epinelps:dev sh scripts/docker-build.sh --platform linux/amd64
# 或直接构建
docker build -t epinelps:latest .
```

构建参数 `DOTNET_VERSION` 默认是 `10.0-noble`，`BUILD_CONFIGURATION` 默认是
`Release`。不要单独改成低于 .NET 10 的基础镜像，项目目标框架为 `net10.0`。

## 使用 Compose 启动

准备好自己的 `gamecommon.json`，设置文件的绝对路径：

```sh
GAMECOMMON_PATH=/absolute/path/gamecommon.json docker compose up -d --build
docker compose logs -f epinelps
```

也可以把文件放到仓库根目录的 `./gamecommon.json`，直接执行
`docker compose up -d --build`。映射来源必须是已存在、容器用户可读的文件；
Compose 不会把缺失的文件自动创建为目录。需要长期使用自定义路径时，在根目录
`.env` 中保存 `GAMECOMMON_PATH=/absolute/path/gamecommon.json`。

默认仅向本机发布 `80` 和 `443` 端口；管理页面地址为
`https://127.0.0.1/admin/`。如需局域网客户端访问，在 `.env` 中设置
`EPINELPS_BIND_ADDRESS=0.0.0.0`，并将客户端使用的游戏域名解析到服务器地址。

可选 Compose 环境变量：

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `GAMECOMMON_PATH` | `./gamecommon.json` | 用户自行提供的文件路径 |
| `EPINELPS_IMAGE` | `epinelps:latest` | 本地或远程镜像名 |
| `EPINELPS_BIND_ADDRESS` | `127.0.0.1` | 宿主机发布端口的地址 |
| `EPINELPS_HTTP_PORT` | `80` | 宿主机 HTTP 端口 |
| `EPINELPS_HTTPS_PORT` | `443` | 宿主机 HTTPS 端口 |

容器内监听 `8080` / `8443`，以非 root 用户 `app`（UID 1654）运行。
修改宿主机端口不会修改游戏客户端内置的地址；正常连接游戏通常仍需要
`80` / `443`。首次启动会下载静态资源，完成初始化前健康检查可能尚未通过。

## 直接使用 docker run

```sh
docker run -d \
  --name epinelps \
  --restart unless-stopped \
  -p 127.0.0.1:80:8080 \
  -p 127.0.0.1:443:8443 \
  --mount type=volume,source=epinelps-data,target=/data \
  --mount type=bind,source=/absolute/path/gamecommon.json,target=/app/gamecommon.json,readonly \
  epinelps:latest
```

`gamecommon.json` 未正确挂载或为空时，入口脚本会给出明确提示并以状态码 1
退出。构建成功不代表游戏数据已配置完成；完整启动还需要匹配当前游戏版本的
文件和资源网络访问。

## 数据持久化与升级

Compose 使用命名卷 `epinelps-data`（实际名称包含 Compose 项目前缀），其中保存：

| `/data` 内的路径 | 内容 |
| --- | --- |
| `epinelps.db`、`epinelps.db-*` | SQLite 数据库及事务文件 |
| `db.json` | 用户游戏进度、服务端配置及密钥 |
| `gameconfig.json`、`gameversion.json` | 可写的游戏配置 |
| `site.pfx` | 服务端证书 |
| `cache/` | 下载的游戏资源 |
| `logs/` | 日志 |
| `keys/` | ASP.NET Core Data Protection 密钥 |

入口脚本只在文件不存在时初始化默认配置和证书，重启或更换镜像不会覆盖已有
配置。升级游戏版本时，应同时检查卷中的 `gameconfig.json`、`gameversion.json`
是否需要更新为新镜像内 `/opt/epinelps-defaults/` 的版本。

备份时先停止服务，保证数据库与 JSON 存档一致：

```sh
docker compose stop epinelps
mkdir -p backup
docker compose cp epinelps:/data/. ./backup/
docker compose start epinelps
```

用户自行挂载的 `gamecommon.json` 需另行备份。`docker compose down` 会保留命名卷；
`docker compose down -v` 会删除命名卷及其中的数据。

如改为绑定宿主机目录到 `/data`，须先创建目录并允许 UID 1654 写入。
不要把数据卷挂载到 `/app`，否则会遮住镜像内的程序文件。

使用其他数据库时，可通过容器环境变量
`ConnectionStrings__EpinelPSConnectionType` 和
`ConnectionStrings__EpinelPSConnection` 覆盖默认 SQLite 配置；`db.json`
仍需持久化。

## GitHub Actions 与 GHCR

工作流文件为 `.github/workflows/docker.yml`：

- 向 `main` 推送：构建两个 Linux 架构，并发布 `main`、`latest`、`sha-<短提交号>`。
- 推送 `v*` 标签：构建并发布同名标签及 SHA 标签，例如 `v0.149.0`。
- 向 `main` 提交 Pull Request：验证构建，不登录 GHCR，不推送镜像。
- 手动执行 `workflow_dispatch`：构建并发布所选分支或标签；仅默认分支更新 `latest`。

镜像名根据仓库名自动转为小写。此仓库首次成功发布后的地址为：

```text
ghcr.io/hoshizukimio/epinelps:latest
```

工作流使用 GitHub 自动提供的 `GITHUB_TOKEN` 与 `packages: write` 权限，
无需额外配置 Docker Hub 账号或 Secret。仓库或组织策略需要允许工作流写入
Packages；若同名包已存在，需要确保该仓库具有该包的 Actions 访问权限。
若要允许其他用户匿名拉取，在包设置中将可见性设为 Public；私有包拉取需要登录
GHCR 并具有读取该包的权限。

发布成功后，可复用同一份 Compose 文件直接拉取镜像运行：

```sh
EPINELPS_IMAGE=ghcr.io/hoshizukimio/epinelps:latest \
GAMECOMMON_PATH=/absolute/path/gamecommon.json \
docker compose up -d --no-build --pull always
```

每次执行该命令需提供相同环境变量，或将它们保存到 `.env`。
Actions 使用 Buildx 的 GHA 缓存，并将第三方 Actions 固定到具体提交。
完整游戏启动验证需用户自行挂载游戏数据后执行；CI 负责镜像编译构建。

参考：[Docker 的 GitHub Actions 集成](https://docs.docker.com/build/ci/github-actions/)、
[GHCR 认证与镜像管理](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)。
