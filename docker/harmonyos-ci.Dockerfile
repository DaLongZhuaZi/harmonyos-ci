# HarmonyOS CI 镜像(多 API 版本 / multi-API)
#
# 用途: 在 GitHub Actions 上云端构建 HarmonyOS 工程, 等价于本机 DevEco Studio 工具链
#   (hvigor / ohpm / SDK / hap-sign-tool)。通过 --build-arg CLT_ZIP_URL 传入不同 API
#   版本的 command-line-tools, 构建出 ghcr.io/<owner>/harmonyos-ci:<tag> 的对应 tag。
#
# 构建(tag 由调用方决定, 如 api23 / api26):
#   docker build --build-arg CLT_ZIP_URL=<分片直链, 空格分隔> -t harmonyos-ci:<tag> .
#   支持 zip 与 tar.gz 两种归档及其分片, 可附 *.sha256 校验直链。
#
# 本地离线构建(已手工下载好归档时, 免二次下载): 把归档放进 docker/local-archive/,
# 然后:
#   docker build -f docker/harmonyos-ci.Dockerfile --target runtime \
#     --build-arg CLT_LOCAL_ARCHIVE=ohos-sdk-linux-amd64.tar.gz \
#     --build-arg CLT_VERSION=26.0.0.821 \
#     -t harmonyos-ci:api26r docker
#
# command-line-tools 来源(必须与工程 compatibleSdkVersion 匹配的 Linux x86-64 版本):
#   - 华为官方 "获取命令行工具" 页面(链接带时效签名, 需自行转存):
#     https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-commandline-get
#   - 社区镜像(推荐, 直链稳定; 本仓库各 tag 实际使用):
#     ErBWs/ohos-sdk        -> tar.gz.aa/.ab 分片 + .sha256(全版本, 含 API 26)
#     jerry-271828/harmonyos-commandline-tools -> zip 分片(API 26 Beta1)
# 版本对照表见仓库根 README.md「镜像 / Images」。
# 注意: 不要把具体下载 URL 固化进仓库(通过 workflow input / secret 传入)。

FROM ubuntu:24.04 AS toolchain

# command-line-tools linux x64 归档的下载直链(必须通过 --build-arg 传入)
ARG CLT_ZIP_URL
# 可选: 本地归档文件名(放在 docker/local-archive/ 下)。给了它就走本地文件, 不联网。
ARG CLT_LOCAL_ARCHIVE=""
# command-line-tools 版本号(用于 OCI version label, 可选)
ARG CLT_VERSION=""
# 镜像双语描述(用于 OCI description label, 按 tag 传入不同的内容)
ARG CLT_DESC=""

# 基础依赖: JDK 17 供 hap-sign-tool 签名; git/python3 供 actions/checkout 与仓库内 CI 脚本;
# libGL/EGL/GLES + X11/GBM 等 headless 图形运行库为 SDK 资源编译器(restool/
# image_transcoder)必需, 缺失会报 'libGL.so.1: cannot open shared object file'(裸容器 CI 常见坑)。
# 分两组安装便于失败定位; 显式确保 universe 组件; 关闭 pty 使 apt 输出可被 Actions 日志捕获。
RUN sed -i 's|Components: main.*|Components: main universe restricted multiverse|' /etc/apt/sources.list.d/*.sources 2>/dev/null || true \
    && apt-get update -o Dpkg::Use-Pty=0 \
    && apt-get install -y --no-install-recommends -o Dpkg::Use-Pty=0 \
         openjdk-17-jdk-headless unzip curl git ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update -o Dpkg::Use-Pty=0 \
    && apt-get install -y --no-install-recommends -o Dpkg::Use-Pty=0 \
         libgl1 libegl1 libgles2 libglx0 libglib2.0-0 \
         libx11-6 libxext6 libxrender1 libxrandr2 libxfixes3 libxi6 libxcursor1 \
         libxcomposite1 libxdamage1 libxtst6 libxkbcommon0 \
         libgbm1 libdrm2 fontconfig fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# 下载、拼接、校验并解压 command-line-tools, 自动判型 zip / tar.gz。
# CLT_ZIP_URL: 以空格分隔的分片直链, 按顺序 cat 拼接还原完整归档:
#   - tar.gz 分片: ...ohos-sdk-linux-amd64.tar.gz.aa / .ab (ErBWs/ohos-sdk)
#   - zip 分片:    ...clt.zip.part00 / .part01 (jerry-271828 社区镜像)
#   可在末尾附加一个 *.sha256 的直链做完整性校验。
# CLT_LOCAL_ARCHIVE 非空时直接使用构建上下文里的本地归档(离线构建)。
# 解压后统一归一化到 /opt/command-line-tools(bin/ tool/ sdk/ 结构)。
# 本地归档目录: 常规情况下只有占位文件 .gitkeep, COPY 恒有匹配, 不破坏联网构建路径。
# Local-archive dir: normally just the .gitkeep placeholder, so COPY always matches
# and the online (URL) build path is unaffected.
COPY local-archive/ /tmp/local-clt/

RUN set -eux; \
    mkdir -p /tmp/clt; cd /tmp/clt; \
    ARCHIVE=clt.tar.gz; \
    if [ -n "$CLT_LOCAL_ARCHIVE" ]; then \
      cp "/tmp/local-clt/$CLT_LOCAL_ARCHIVE" "$ARCHIVE"; \
    else \
      test -n "$CLT_ZIP_URL"; \
      i=0; for u in $CLT_ZIP_URL; do \
        case "$u" in *.sha256) curl -fL --retry 3 --retry-delay 5 -o sha256.txt "$u";; \
        *) curl -fL --retry 3 --retry-delay 5 -o "part.$i" "$u"; i=$((i+1));; \
        esac; \
      done; \
      for u in $CLT_ZIP_URL; do FIRURL="$u"; break; done; \
      case "$FIRURL" in *.tar*) ARCHIVE=clt.tar.gz;; *) ARCHIVE=clt.zip;; esac; \
      : > "$ARCHIVE"; \
      for f in part.*; do cat "$f" >> "$ARCHIVE"; done; \
      if [ -f sha256.txt ]; then \
        EXPECT=$(awk '{print $1}' sha256.txt); \
        ACTUAL=$(sha256sum "$ARCHIVE" | awk '{print $1}'); \
        test "$EXPECT" = "$ACTUAL"; \
      fi; \
    fi; \
    mkdir -p out; \
    case "$ARCHIVE" in *.tar.gz|*.tgz) tar -xzf "$ARCHIVE" -C out;; *) unzip -q "$ARCHIVE" -d out;; esac; \
    CLTROOT=""; \
    for f in $(find out -maxdepth 5 -type f -name hvigorw -path '*/bin/*'); do \
      d=$(dirname "$(dirname "$f")"); \
      if [ -x "$d/bin/hvigorw" ] && [ -d "$d/sdk" ]; then CLTROOT="$d"; break; fi; \
    done; \
    if [ -z "$CLTROOT" ]; then \
      echo "ERROR: 定位工具链根目录失败 / cannot locate toolchain root"; \
      echo "--- 候选 bin/hvigorw ---"; \
      find out -maxdepth 6 -type f -name hvigorw || true; \
      echo "--- out 顶层 ---"; ls -la out; \
      exit 1; \
    fi; \
    echo "toolchain root = $CLTROOT"; \
    mv "$CLTROOT" /opt/command-line-tools; \
    ls -la /opt/command-line-tools/bin/; \
    test -x /opt/command-line-tools/bin/hvigorw; \
    test -d /opt/command-line-tools/sdk; \
    rm -rf /tmp/clt

FROM toolchain AS runtime

# DEVECO_SDK_HOME 必须指向包含 default/ 的 sdk 根目录(而不是 sdk/default)
ENV DEVECO_SDK_HOME=/opt/command-line-tools/sdk
ENV PATH=/opt/command-line-tools/bin:/opt/command-line-tools/tool/node/bin:/opt/command-line-tools/tool/hvigor/bin:/opt/command-line-tools/tool/ohpm/bin:$PATH

# @ohos 域包走华为 npm 镜像(hvigor / ohpm 解析 @ohos/* 依赖依赖这条配置)
RUN echo "@ohos:registry=https://repo.harmonyos.com/npm/" >> /root/.npmrc

# 预热: hvigor 首次运行会自检并初始化 ~/.hvigor, 预热避免每次 CI 冷启动。
# 预热失败不应让整次镜像构建失败(离线/网络抖动时仍保留可用镜像)。
RUN hvigorw --version || echo "warn: hvigorw --version failed (will warm up at first CI run / 首次 CI 运行时会自检)"

# 签名工具固定路径(需 JDK 17):
#   /opt/command-line-tools/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar

# OCI 元数据: 这些 label 会显示在 GitHub Package 页面(ghcr.io)的描述区。
# OCI labels: these populate the GitHub Package (ghcr.io) page description.
LABEL org.opencontainers.image.title="harmonyos-ci (HarmonyOS 构建镜像 / HarmonyOS CI images)" \
      org.opencontainers.image.description="${CLT_DESC}" \
      org.opencontainers.image.version="${CLT_VERSION}" \
      org.opencontainers.image.source="https://github.com/DaLongZhuaZi/harmonyos-ci" \
      org.opencontainers.image.documentation="https://github.com/DaLongZhuaZi/harmonyos-ci" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /workspace
CMD ["/bin/bash"]