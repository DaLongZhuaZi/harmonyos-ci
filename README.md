# harmonyos-ci（HarmonyOS CI 工具链镜像 / CI toolchain images）

本仓库统一维护 HarmonyOS 的 **command-line-tools 编译工具链 Docker 镜像**，
用于在 GitHub Actions 上**无需 DevEco Studio** 云端构建 HarmonyOS 工程，产出 `.hap`。
This repo maintains the command-line-tools Docker images used to build HarmonyOS apps in CI **without DevEco Studio**.

## 镜像 / Images

| Tag | command-line-tools | 适用 SDK / For SDK | 消费者 / Consumers |
|---|---|---|---|
| `api26` | 26.0.0.461 | HarmonyOS 26.0.0（API 26 Beta1） | NGF、ASFWorkshop |
| `api26b2` | 26.0.0.621 | HarmonyOS 26.0.0（API 26 Beta2） | — |
| `api24` | 6.1.1.300 | HarmonyOS 6.1.1（API 24） | — |
| `api23` | 6.1.0.818 | HarmonyOS 6.1.0（API 23） | Coder |

Package 地址 / Package URL: https://github.com/DaLongZhuaZi/NGF/pkgs/container/harmonyos-ci
（镜像名 `ghcr.io/dalongzhuazi/harmonyos-ci`，public，匿名可拉取复用。）

## 目录 / Layout

```
harmonyos-ci/
├── docker/harmonyos-ci.Dockerfile   # 通用 Dockerfile（zip / tar.gz，分片 + sha256）
├── docker/README.md                 # 镜像说明（双语）
├── .github/workflows/docker-image.yml  # 构建并推送镜像（workflow_dispatch）
└── README.md
```

## 构建新 tag / Building a tag

**前置**：在仓库 Secrets 配置 `GHCR_PAT`（一个 user 级 Personal Access Token，scope 至少 `write:packages`）。因 `ghcr.io/dalongzhuazi/harmonyos-ci` 这个 package 由 NGF 仓库首次创建，跨仓库写同名 package 需用 PAT 而非 repo-scoped 的 GITHUB_TOKEN。

1. 取得与目标 API 匹配的 Linux (x86-64) command-line-tools 分片直链（社区镜像或华为官方）。
2. 运行本仓库的 **Build CI image** workflow（workflow_dispatch）：
   - `clt_zip_url`：分片直链，空格分隔（可附 `.sha256` 校验 URL）
   - `image_tag`：目标 tag（如 `api23`、`api26`）

## 复用到你的项目 / Reusing in your project

复制消费方模板（`.github/workflows/build.yml` / `sign-and-release.yml` / `.github/scripts/strip_signing.py`），
把镜像引用指向 `ghcr.io/dalongzhuazi/harmonyos-ci:<你的 API tag>` 即可。
详见任一消费方仓库（如 NGF）的 `docs/CI_Guide.md` / `docs/CI_Guide.en.md`。
