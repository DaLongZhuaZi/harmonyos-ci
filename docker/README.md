# harmonyos-ci (HarmonyOS CI 镜像 / CI images)

本镜像用于在 GitHub Actions 上**无需 DevEco Studio** 即可构建 HarmonyOS 工程，产出 `.hap` 产物。
These images build HarmonyOS apps **without DevEco Studio** inside GitHub Actions, producing `.hap` artifacts.

**Package 地址 / Package URL**：https://github.com/DaLongZhuaZi/harmonyos-ci/pkgs/container/harmonyos-ci

## 可用 tag / Available tags

| Tag | command-line-tools | 适用 SDK / For SDK | 来源 / Source |
|---|---|---|---|
| `api26r` | 26.0.0.821 | HarmonyOS 26.0.0（API 26 **正式版**） | ErBWs/ohos-sdk `26.0.0.821` |
| `api26b2` | 26.0.0.621 | HarmonyOS 26.0.0（API 26 Beta2） | ErBWs/ohos-sdk `26.0.0.621` |
| `api26` | 26.0.0.461 | HarmonyOS 26.0.0（API 26 Beta1） | jerry-271828 `v26.0.0.461` |
| `api24` | 6.1.1.300 | HarmonyOS 6.1.1（API 24） | ErBWs/ohos-sdk |
| `api23` | 6.1.0.818 | HarmonyOS 6.1.0（API 23） | ErBWs/ohos-sdk `6.1.0.818` |

**新工程用 `api26r`**：`26.0.0.821` 与 DevEco Studio 26 Release 内置 SDK（`build.txt`
`DS-261.23567.138.305.2600821`，SDK `26.0.0.105` / apiVersion 26 / Release）一致，
工程 `compatibleSdkVersion` 写 `26.0.0`（**实测必须写这个形式**；写成 `26.0.0(26)` 会被 hvigor 拒绝：`api version parameter is illegal`）。

所有 tag 均 `public`，任何仓库可匿名拉取（复用）。
All tags are `public` and pullable anonymously (reusable across repos).

> 该 package 归 **NGF 仓库** 所有（由 NGF 的 `.github/workflows/docker-image.yml` 首次创建）；
> 现在镜像的构建/维护统一在 **本仓库**（harmonyos-ci），其它项目（ASFWorkshop / Coder / NGF）作为
> **消费者**拉取对应 tag，因此它们的仓库页面不会出现此 package——这是「一个镜像、多仓复用」的正确形态。
> The package was **first created by the NGF repo**; build/maintenance now lives in **this repo**,
> while other projects (ASFWorkshop / Coder / NGF) just pull the tag they need as consumers.

## 内含 / Contents

| 组件 / Component | 说明 / Description |
|---|---|
| command-line-tools | 随 tag 锁定、可复现 / pinned per tag |
| hvigor / hvigorw | 构建编排（等价 Android 的 gradle）/ build orchestration (= Android gradle) |
| ohpm | 依赖管理（等价 Android 的 maven）/ package manager (= Android maven) |
| HarmonyOS SDK | 与 tag 匹配的 API 版本 / matching API per tag |
| hap-sign-tool.jar | JDK 17 运行时签名工具 / signing tool (requires JDK 17) |
| libGL/EGL/GLES + X11/GBM | SDK 资源编译器 restool 所需的 headless 图形运行库 / headless GL libs required by restool |

工具链固定安装在 `/opt/command-line-tools`，环境变量已就绪：
`DEVECO_SDK_HOME=/opt/command-line-tools/sdk`，`PATH` 含 `bin`、`tool/node/bin`、`tool/ohpm/bin`。
签名工具路径：`/opt/command-line-tools/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar`

## 用途 / Usage

由各消费仓库的 `.github/workflows/build.yml` 与 `.github/workflows/sign-and-release.yml` 自动使用，
无需手动操作（模板见本仓库 `.github/workflows/`）。
Each consumer repo's `build.yml` / `sign-and-release.yml` uses it automatically -
templates live in this repo's `.github/workflows/`.

本地手动构建（免 DevEco Studio）/ Local manual build:
```bash
# API 26 正式版工程 / API 26 release project
docker run --rm -v "$PWD":/workspace ghcr.io/dalongzhuazi/harmonyos-ci:api26r \
  bash -lc 'ohpm install --all && hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon'
```
> Windows PowerShell 用 `-v "${PWD}:/workspace"`。构建产物在
> `entry/build/default/outputs/default/entry-default-unsigned.hap`（未签名，装前需重新签名）。

## 构建方式 / How the image is built

`docker/harmonyos-ci.Dockerfile` 支持两种取得 command-line-tools 的方式：
The Dockerfile accepts the toolchain either way:

1. **联网**：`--build-arg CLT_ZIP_URL="<分片直链 空格分隔> [<.sha256 直链>]"`
   （CI workflow 走这条；分片按顺序拼接、可选 sha256 校验、自动判型 zip / tar.gz）
2. **离线**：把归档放进 `docker/local-archive/`，再加
   `--build-arg CLT_LOCAL_ARCHIVE=<归档文件名>`（本地验证 Dockerfile 用，免二次下载）

完整步骤见仓库根 [README.md](../README.md) 与 [docs/CI_Guide.md](../docs/CI_Guide.md)。

## 为新 API 版本新增 tag / Adding a tag for a new API version

1. 取得对应版本的 Linux (x86-64) command-line-tools 直链（社区镜像分片、空格分隔，也可附 `.sha256` 校验）：
   - API 26 正式版：`ErBWs/ohos-sdk` 的 `26.0.0.821`（tar.gz.aa / .ab + .sha256）
   - API 26 Beta1：`jerry-271828/harmonyos-commandline-tools` 的 `v26.0.0.461`（zip 分片）
   - API 23：`ErBWs/ohos-sdk` 的 `6.1.0.818`（tar.gz.aa / .ab 分片 + .sha256）
2. 在 [`.github/workflows/docker-image.yml`](../.github/workflows/docker-image.yml) 的
   「校验镜像 tag」列表与「解析镜像描述」case 中登记新 tag。
3. 运行本仓库的 **Build CI image** workflow（workflow_dispatch），
   `clt_zip_url` 填对应直链、`image_tag` 填新 tag（如 `api27`）。

> GitHub 包页面当前渲染的是本仓库根目录 `README.md`；镜像描述来自 OCI label（见本目录 Dockerfile）。
> 完整中文/英文步骤见 [docs/CI_Guide.md](../docs/CI_Guide.md) / [docs/CI_Guide.en.md](../docs/CI_Guide.en.md)。
