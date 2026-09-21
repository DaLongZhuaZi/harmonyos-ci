# CI 免 DevEco Studio 构建指南

> 本指南说明如何用本仓库发布的 **command-line-tools 镜像**在 GitHub Actions 上构建 HarmonyOS 工程,
> 全程**无需安装 DevEco Studio**。
> This guide covers building HarmonyOS apps on GitHub Actions with the images published by this
> repo - **no DevEco Studio required**. English: [CI_Guide.en.md](CI_Guide.en.md).

## 1. 概览

本仓库产出的是**工具链镜像**, 不是应用工程。它把「hvigor + ohpm + HarmonyOS SDK + hap-sign-tool」
固化进一个 Docker 镜像, 供任意 HarmonyOS 仓库在 CI 里复用:

| 镜像 tag | command-line-tools | 适用 SDK | 说明 |
|---|---|---|---|
| `api26r` | 26.0.0.821 | HarmonyOS 26.0.0(API 26 正式版) | 与 DevEco Studio 26 Release 内置 SDK 一致 |
| `api26b2` | 26.0.0.621 | HarmonyOS 26.0.0(API 26 Beta2) | |
| `api26` | 26.0.0.461 | HarmonyOS 26.0.0(API 26 Beta1) | 旧 Beta1 工程用 |
| `api24` | 6.1.1.300 | HarmonyOS 6.1.1(API 24) | |
| `api23` | 6.1.0.818 | HarmonyOS 6.1.0(API 23) | |

镜像地址: `ghcr.io/dalongzhuazi/harmonyos-ci:<tag>`(public, 匿名可拉)。

**选哪个 tag**: 看工程的 `build-profile.json5` 里 `products[].compatibleSdkVersion`,
与上表「适用 SDK」对齐即可; 拿不准就用最新的 `api26r`。

## 2. 前置条件

- 工程能通过 `hvigorw assembleHap` 构建(本机用 DevEco Studio 能出包即可)。
- 仓库 Actions 允许拉取 public 镜像(默认允许; 私有镜像才需要 credentials)。

## 3. 复用到你的工程

从本仓库复制三个文件到你的工程, 路径必须一致:

| 从本仓库 | 到你的工程 | 作用 |
|---|---|---|
| `.github/workflows/build.yml` | 同路径 | push/PR 构建未签名 HAP + 滚动 `nightly` Release |
| `.github/workflows/sign-and-release.yml` | 同路径 | push `v*` tag 时签名并发布版本化 Release(可选) |
| `.github/scripts/strip_signing.py` | 同路径 | 剥离本机签名配置, 使 CI 能出**未签名** HAP |

复制后**只需改一行**: 每个 workflow 顶部的 `env.CI_IMAGE` 改成与你工程匹配的 tag:

```yaml
env:
  CI_IMAGE: ghcr.io/dalongzhuazi/harmonyos-ci:api26r
```

> `strip_signing.py` 是**必需**的: DevEco Studio 本机自动签名后会把 `signingConfigs` 写进
> `build-profile.json5`, 里面的 `certpath/profile/storeFile` 指向你本机绝对路径,
> CI 容器里不存在这些文件, 构建会直接失败。该脚本原地删除 `app.signingConfigs` 与
> `products[].signingConfig`, 只改 CI 工作副本, 不影响你本机的签名构建。
> 本地预览改动: `python3 .github/scripts/strip_signing.py build-profile.json5 --check`

## 4. 触发矩阵

| 操作 | 结果 |
|---|---|
| push 到 `main`/`master` | 构建未签名 debug HAP + 更新滚动 `nightly` Release |
| 打开/更新 PR | 仅构建(不发布 Release) |
| 推 `v*` tag | 构建 + 签名(配了 Secrets 时) + 发布版本化 Release |
| 手动 `workflow_dispatch` | 按选择构建; `build.yml` 可用 `image` 输入临时覆盖镜像 |

## 5. 免 DevEco Studio 的三种构建方式

### 方式 A: 云端自动(默认, 零操作)
push 到 `main` 后, Actions 在 ghcr 镜像内执行:
```bash
ohpm install --all
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon --stacktrace
```
产物: `entry/build/default/outputs/default/entry-default-unsigned.hap`, 随 artifact 与 `nightly` Release 分发。

### 方式 B: 本地 Docker(不装 DevEco, 复现云端环境)
```bash
docker run --rm -v "$PWD":/workspace ghcr.io/dalongzhuazi/harmonyos-ci:api26r \
  bash -lc 'ohpm install --all && hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon'
```
> Windows PowerShell 用 `-v "${PWD}:/workspace"`; 路径含空格时注意加引号。

### 方式 C: 本机 DevEco 命令行(已装 DevEco 时)
用 IDE 自带 hvigor, 例如 DevEco Studio 26:
```powershell
$env:DEVECO_SDK_HOME='G:\DevEco Studio 26\DevEco Studio\sdk'
& 'G:\DevEco Studio 26\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon --stacktrace
```
(路径是本机事实, 不同机器以实际安装目录为准。)

## 6. 签名与自动 Release

### 滚动 nightly Release(无需签名, 默认开启)
每次 push `main`/`master`, `build.yml` 的 `release` job 用 `gh release` 重建 `nightly` tag 与
同名额预发布(prerelease), 附带未签名 HAP。

### 版本化 Release + 签名(可选, 需配置 Secrets)
push `v*` tag 触发 `sign-and-release.yml`。所需 Secrets(证书文件 base64 单行, 绝不入库):

| Secret | 内容 | 生成方式 |
|---|---|---|
| `SIGNING_CERT` | `.cer` 公钥证书 | `base64 -w 0 xxx.cer` |
| `SIGNING_PROFILE` | `.p7b` 签名 profile | `base64 -w 0 xxx.p7b` |
| `SIGNING_KEY` | `.p12` 密钥库 | `base64 -w 0 xxx.p12` |
| `SIGNING_KEY_ALIAS` | 密钥别名 | 明文 |
| `KEYSTORE_PASSWORD` | 密钥库口令 | 明文 |
| `KEY_PASSWORD` | 密钥口令 | 明文 |

签名调用的是镜像内固定路径的官方工具(需 JDK 17, 镜像已内置):
`/opt/command-line-tools/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar`

> Secrets 未配齐时, 签名 job 自动跳过并输出指引, **不会**把 tag 构建打红。

## 7. 验证

1. push 后打开 Actions 页, 确认构建 job 为绿色。
2. 下载 artifact(`gh run download <id> -n hap-unsigned`)或从 Releases 页取 HAP。
3. 确认 HAP 非空且是合法 ZIP 容器(文件头 `50 4B 03 04` 即 `PK`)。
4. 未签名 HAP 无法直接安装, 需用 DevEco Studio 或 hap-sign-tool 重新签名。

## 8. 排障

| 现象 | 原因与解决 |
|---|---|
| `libGL.so.1: cannot open shared object file` | 裸容器缺 OpenGL 库; 本镜像已内置 `libgl1/libegl1/libgles2` 等, 用本镜像即可 |
| `shopt: not found` | runner 默认 sh(dash) 无 `shopt`; workflow 已设 `defaults.run.shell: bash` |
| `hvigor 版本不匹配 / unsupported model version` | command-line-tools 与工程 `compatibleSdkVersion` 不匹配; 换对应 tag(如 API 26 正式版用 `api26r`) |
| `api version parameter is illegal! Expected format: <major>[.<minor>][.<patch>]` | 工程 `compatibleSdkVersion` 用了带括号形式 `26.0.0(26)`。**API 26 工程必须写 `"compatibleSdkVersion": "26.0.0"`**(镜像内实测: `26.0.0(26)` / `26` / 数字 `26` 全被拒绝, 只有 `26.0.0` 能进编译) |
| `The modelVersion in hvigor-config.json5 is X, and the modelVersion in oh-package.json5 is Y` | 两处 `modelVersion` 必须一致: `oh-package.json5` 与 `hvigor/hvigor-config.json5`; API 26 工程统一写 `26.0.0` |
| 构建报找不到证书/`signingConfigs` 相关错误 | 没跑 `strip_signing.py`, 或 `build-profile.json5` 路径不是仓库根 |
| 镜像拉取失败 | 确认 tag 拼写; 镜像 public, 匿名可拉。tag 是否已构建见本仓库 Releases 页 |
| `entry-default-unsigned.hap` 无法安装 | 未签名 HAP 需先签名(DevEco Studio 或 hap-sign-tool) |

## 9. 维护本仓库(新增/更新镜像 tag)

1. 取与目标 API 匹配的 **Linux x86-64** command-line-tools 分片直链(社区镜像或华为官方)。
2. 运行本仓库的 **Build CI image** workflow(`workflow_dispatch`):
   - `image_tag`: 目标 tag(必须在 workflow「校验镜像 tag」步骤的已知列表里)
   - `clt_zip_url`: 分片直链, 空格分隔(可附 `.sha256` 校验直链)
   - `clt_version`: 版本号(用于 Release 记录与 OCI version label)
3. 成功后会在本仓库发布一个同名正式 Release 作为构建公告, 镜像推送到 `ghcr.io/dalongzhuazi/harmonyos-ci:<tag>`。

新增 tag 时记得同步改三处: workflow 的**校验**列表、workflow 的**描述** case、以及根 `README.md` 与
`docker/README.md` 的镜像表。

> `GHCR_PAT`: 因该 package 由 NGF 仓库首次创建, 跨仓库写同名 package 会被 `deny(write_package)`,
> 所以 workflow 用 user 级 PAT(scope 至少 `write:packages`)而非 repo-scoped 的 `GITHUB_TOKEN`。
