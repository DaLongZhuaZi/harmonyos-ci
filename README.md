# harmonyos-ci（HarmonyOS CI 工具链镜像 / CI toolchain images）

本仓库统一维护 HarmonyOS 的 **command-line-tools 编译工具链 Docker 镜像**，
用于在 GitHub Actions 上**无需 DevEco Studio** 云端构建 HarmonyOS 工程，产出 `.hap`。
This repo maintains the command-line-tools Docker images used to build HarmonyOS apps in CI **without DevEco Studio**.

## 镜像 / Images

| Tag | command-line-tools | 适用 SDK / For SDK | 来源 / Source |
|---|---|---|---|
| `api26r` | 26.0.0.821 | HarmonyOS 26.0.0（API 26 **正式版**） | [ErBWs/ohos-sdk](https://github.com/ErBWs/ohos-sdk/releases/tag/26.0.0.821) |
| `api26b2` | 26.0.0.621 | HarmonyOS 26.0.0（API 26 Beta2） | [ErBWs/ohos-sdk](https://github.com/ErBWs/ohos-sdk/releases/tag/26.0.0.621) |
| `api26` | 26.0.0.461 | HarmonyOS 26.0.0（API 26 Beta1） | [jerry-271828](https://github.com/jerry-271828/harmonyos-commandline-tools/releases/tag/v26.0.0.461) |
| `api24` | 6.1.1.300 | HarmonyOS 6.1.1（API 24） | ErBWs/ohos-sdk |
| `api23` | 6.1.0.818 | HarmonyOS 6.1.0（API 23） | [ErBWs/ohos-sdk](https://github.com/ErBWs/ohos-sdk/releases/tag/6.1.0.818) |

**新工程默认用 `api26r`**（API 26 正式版）。
Package 地址 / Package URL：https://github.com/DaLongZhuaZi/harmonyos-ci/pkgs/container/harmonyos-ci
（镜像名 `ghcr.io/dalongzhuazi/harmonyos-ci`，public，匿名可拉取复用，已实测 `docker pull` 免登录成功。）

### 已发布 tag / Published tags

| Tag | command-line-tools | 发布 Release | 说明 |
|---|---|---|---|
| `api26r` | 26.0.0.821 | [镜像构建: api26r](https://github.com/DaLongZhuaZi/harmonyos-ci/releases/tag/api26r) | **API 26 正式版，推荐** |
| `api26b2` | 26.0.0.621 | [api26b2](https://github.com/DaLongZhuaZi/harmonyos-ci/releases/tag/api26b2) | API 26 Beta2 |
| `api26` | 26.0.0.461 | [api26](https://github.com/DaLongZhuaZi/harmonyos-ci/releases/tag/api26) | API 26 Beta1 |
| `api24` | 6.1.1.300 | [api24](https://github.com/DaLongZhuaZi/harmonyos-ci/releases/tag/api24) | API 24 |
| `api23` | 6.1.0.818 | [api23](https://github.com/DaLongZhuaZi/harmonyos-ci/releases/tag/api23) | API 23 |

> `api26r` 已本地端到端验证：容器内 `ohpm install --all` + `hvigorw assembleHap` 成功产出
> `entry-default-unsigned.hap`（112,803 字节，PK 魔数，13 条目，`minAPIVersion=260000026`）。
> `api26r` has been verified end-to-end locally: a real HAP is produced inside the image.

## 目录 / Layout

```
harmonyos-ci/
├── docker/harmonyos-ci.Dockerfile   # 通用 Dockerfile（zip / tar.gz，分片 + sha256，支持离线构建）
├── docker/README.md                 # 镜像说明（双语）
├── docker/local-archive/            # 本地离线构建用归档放置目录（仅 .gitkeep 入库）
├── .github/workflows/
│   ├── docker-image.yml             # 构建并推送镜像（workflow_dispatch）
│   ├── build.yml                    # 消费方模板：构建未签名 HAP + 滚动 nightly Release
│   └── sign-and-release.yml         # 消费方模板：签名 + 版本化 Release
├── .github/scripts/strip_signing.py # 剥离本机签名配置（产出未签名 HAP）
├── docs/CI_Guide.md                 # 完整中文指南（构建 / 签名 / 排障 / 维护）
├── docs/CI_Guide.en.md              # 完整英文指南
└── README.md
```

> ⚠️ 本仓库的 `build.yml` / `sign-and-release.yml` 是**给消费方复制走的模板**，
> 它们构建的是「当前仓库」的 HarmonyOS 工程；在本仓库自身不会触发（本仓库没有应用工程）。
> The two workflow files are **consumer templates** meant to be copied into an app repo.

## 构建新 tag / Building a tag

**前置**：在仓库 Secrets 配置 `GHCR_PAT`（一个 user 级 Personal Access Token，scope 至少 `write:packages`）。因 `ghcr.io/dalongzhuazi/harmonyos-ci` 这个 package 由 NGF 仓库首次创建，跨仓库写同名 package 需用 PAT 而非 repo-scoped 的 `GITHUB_TOKEN`。

1. 取得与目标 API 匹配的 Linux (x86-64) command-line-tools 分片直链（社区镜像或华为官方）。
2. 运行本仓库的 **Build CI image** workflow（workflow_dispatch）：
   - `image_tag`：目标 tag（必须在 workflow 的已知 tag 列表内，如 `api26r`）
   - `clt_zip_url`：分片直链，空格分隔（可附 `.sha256` 校验 URL）
   - `clt_version`：版本号（如 `26.0.0.821`）

### 本地构建（免联网，用于验证 Dockerfile）

```bash
# 1) 下载并核对官方 sha256 后, 把归档放进 docker/local-archive/
curl -fL -o docker/local-archive/ohos-sdk-linux-amd64.tar.gz.aa <...tar.gz.aa>
curl -fL -o docker/local-archive/ohos-sdk-linux-amd64.tar.gz.ab <...tar.gz.ab>
cat docker/local-archive/ohos-sdk-linux-amd64.tar.gz.a? > docker/local-archive/ohos-sdk-linux-amd64.tar.gz

# 2) 离线构建
docker build -f docker/harmonyos-ci.Dockerfile --target runtime \
  --build-arg CLT_LOCAL_ARCHIVE=ohos-sdk-linux-amd64.tar.gz \
  --build-arg CLT_VERSION=26.0.0.821 \
  -t harmonyos-ci:api26r docker
```

也可以不落地文件，直接让容器联网下载：

```bash
docker build -f docker/harmonyos-ci.Dockerfile --target runtime \
  --build-arg CLT_ZIP_URL="https://github.com/ErBWs/ohos-sdk/releases/download/26.0.0.821/ohos-sdk-linux-amd64.tar.gz.aa https://github.com/ErBWs/ohos-sdk/releases/download/26.0.0.821/ohos-sdk-linux-amd64.tar.gz.ab https://github.com/ErBWs/ohos-sdk/releases/download/26.0.0.821/ohos-sdk-linux-amd64.tar.gz.sha256" \
  -t harmonyos-ci:api26r docker
```

## 复用到你的项目 / Reusing in your project

复制以下三个文件到你的工程（路径保持一致），然后把 workflow 顶部的 `env.CI_IMAGE` 改成对应的 tag：

| 从本仓库复制 | 作用 |
|---|---|
| [`.github/workflows/build.yml`](.github/workflows/build.yml) | 构建未签名 HAP + 滚动 `nightly` Release |
| [`.github/workflows/sign-and-release.yml`](.github/workflows/sign-and-release.yml) | `v*` tag 时签名并发布版本化 Release（可选） |
| [`.github/scripts/strip_signing.py`](.github/scripts/strip_signing.py) | 剥离本机签名配置（**必需**，否则 CI 找不到本机证书会构建失败） |

```yaml
env:
  CI_IMAGE: ghcr.io/dalongzhuazi/harmonyos-ci:api26r   # ← 只改这一行
```

`strip_signing.py` 会原地删除 `build-profile.json5` 里的 `app.signingConfigs` 与
`products[].signingConfig`（DevEco Studio 本机自动签名写入的绝对路径在容器里不存在），
只改 CI 工作副本，不影响本机签名构建。

详见 [`docs/CI_Guide.md`](docs/CI_Guide.md) / [`docs/CI_Guide.en.md`](docs/CI_Guide.en.md)。

## 许可 / License

MIT