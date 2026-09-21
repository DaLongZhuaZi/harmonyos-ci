# CI Build Guide (No DevEco Studio)

> How to build HarmonyOS apps on GitHub Actions using the **command-line-tools images** published by
> this repo - **no DevEco Studio install required**.
> 中文版: [CI_Guide.md](CI_Guide.md).

## 1. Overview

This repo ships **toolchain images**, not app projects. Each image pins
"hvigor + ohpm + HarmonyOS SDK + hap-sign-tool" so any HarmonyOS repo can reuse it in CI:

| Image tag | command-line-tools | For SDK | Notes |
|---|---|---|---|
| `api26r` | 26.0.0.821 | HarmonyOS 26.0.0 (API 26 Release) | matches DevEco Studio 26 bundled SDK |
| `api26b2` | 26.0.0.621 | HarmonyOS 26.0.0 (API 26 Beta2) | |
| `api26` | 26.0.0.461 | HarmonyOS 26.0.0 (API 26 Beta1) | for older Beta1 projects |
| `api24` | 6.1.1.300 | HarmonyOS 6.1.1 (API 24) | |
| `api23` | 6.1.0.818 | HarmonyOS 6.1.0 (API 23) | |

Image ref: `ghcr.io/dalongzhuazi/harmonyos-ci:<tag>` (public, pullable anonymously).

**Which tag?** Check `products[].compatibleSdkVersion` in your `build-profile.json5` and match the
"For SDK" column; if unsure, use the newest (`api26r`).

## 2. Prerequisites

- Your project already builds with `hvigorw assembleHap` (i.e. it produces a HAP in DevEco Studio).
- Actions may pull a public image (default; credentials are only needed for private images).

## 3. Reusing it in your project

Copy three files from this repo into your project, keeping the same paths:

| From this repo | To your project | Purpose |
|---|---|---|
| `.github/workflows/build.yml` | same path | Build unsigned HAP on push/PR + rolling `nightly` release |
| `.github/workflows/sign-and-release.yml` | same path | Sign + versioned release on `v*` tags (optional) |
| `.github/scripts/strip_signing.py` | same path | Strip machine-local signing config so CI can emit an **unsigned** HAP |

Then change exactly **one line**: the `env.CI_IMAGE` at the top of each workflow:

```yaml
env:
  CI_IMAGE: ghcr.io/dalongzhuazi/harmonyos-ci:api26r
```

> `strip_signing.py` is **required**: after DevEco Studio auto-signs locally it writes
> `signingConfigs` into `build-profile.json5`, whose `certpath/profile/storeFile` point at absolute
> paths on your machine. Those files do not exist in the CI container, so the build fails outright.
> The script removes `app.signingConfigs` and `products[].signingConfig` in place - it only touches
> the CI working copy, never your local signed build.
> Preview locally: `python3 .github/scripts/strip_signing.py build-profile.json5 --check`

## 4. Trigger matrix

| Action | Result |
|---|---|
| Push to `main`/`master` | Build unsigned debug HAP + refresh rolling `nightly` release |
| Open/update a PR | Build only (no release) |
| Push a `v*` tag | Build + sign (when secrets are set) + versioned release |
| Manual `workflow_dispatch` | Build on demand; `build.yml` accepts an `image` override input |

## 5. Three ways to build without DevEco Studio

### A. Cloud automatic (default, zero effort)
On push to `main`, Actions runs inside the ghcr image:
```bash
ohpm install --all
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon --stacktrace
```
Output: `entry/build/default/outputs/default/entry-default-unsigned.hap`, shipped via artifact and the `nightly` release.

### B. Local Docker (no DevEco, mirrors the cloud env)
```bash
docker run --rm -v "$PWD":/workspace ghcr.io/dalongzhuazi/harmonyos-ci:api26r \
  bash -lc 'ohpm install --all && hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon'
```
> On Windows PowerShell use `-v "${PWD}:/workspace"` and mind quoting for paths with spaces.

### C. Local DevEco CLI (when DevEco is installed)
Use the IDE's bundled hvigor, e.g. DevEco Studio 26:
```powershell
$env:DEVECO_SDK_HOME='G:\DevEco Studio 26\DevEco Studio\sdk'
& 'G:\DevEco Studio 26\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon --stacktrace
```
(That is a machine-local path; use your actual DevEco install directory.)

## 6. Signing & releases

### Rolling nightly release (no signing needed, on by default)
On every push to `main`/`master`, the `release` job in `build.yml` recreates the `nightly` tag and
its same-named prerelease, attaching the unsigned HAP.

### Versioned release + signing (optional, requires secrets)
Push a `v*` tag to trigger `sign-and-release.yml`. Required secrets (cert files base64-encoded on a
single line, never committed):

| Secret | Content | How to produce |
|---|---|---|
| `SIGNING_CERT` | `.cer` certificate | `base64 -w 0 cert.cer` |
| `SIGNING_PROFILE` | `.p7b` signing profile | `base64 -w 0 profile.p7b` |
| `SIGNING_KEY` | `.p12` keystore | `base64 -w 0 key.p12` |
| `SIGNING_KEY_ALIAS` | key alias | plain text |
| `KEYSTORE_PASSWORD` | keystore password | plain text |
| `KEY_PASSWORD` | key password | plain text |

Signing uses the official tool at a fixed path inside the image (needs JDK 17, already installed):
`/opt/command-line-tools/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar`

> If the secrets are incomplete the signing job skips with a notice instead of failing the tag build.

## 7. Verification

1. After pushing, check the Actions page - the build job should be green.
2. Grab the HAP from the artifact (`gh run download <id> -n hap-unsigned`) or the Releases page.
3. Confirm it is non-empty and a valid ZIP container (magic `50 4B 03 04` = `PK`).
4. Unsigned HAPs cannot be installed directly - re-sign with DevEco Studio or hap-sign-tool.

## 8. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `libGL.so.1: cannot open shared object file` | Bare container lacks OpenGL; this image bundles `libgl1/libegl1/libgles2`, so use it |
| `shopt: not found` | Runner default `sh` (dash) lacks `shopt`; workflows set `defaults.run.shell: bash` |
| hvigor version mismatch / unsupported model version | command-line-tools does not match `compatibleSdkVersion`; switch tag (API 26 release = `api26r`) |
| `api version parameter is illegal! Expected format: <major>[.<minor>][.<patch>]` | The project uses the bracketed form `26.0.0(26)`. **API 26 projects must use `"compatibleSdkVersion": "26.0.0"`** (verified inside the image: `26.0.0(26)`, `26`, and numeric `26` are all rejected - only `26.0.0` compiles) |
| `The modelVersion in hvigor-config.json5 is X, and the modelVersion in oh-package.json5 is Y` | `modelVersion` must match across `oh-package.json5` and `hvigor/hvigor-config.json5`; use `26.0.0` for API 26 projects |
| Errors about missing certs / `signingConfigs` | `strip_signing.py` was not run, or `build-profile.json5` is not at the repo root |
| Image pull fails | Check the tag spelling; the image is public. Built tags appear on this repo's Releases page |
| `entry-default-unsigned.hap` won't install | Unsigned HAPs must be signed first (DevEco Studio or hap-sign-tool) |

## 9. Maintaining this repo (adding/updating an image tag)

1. Get the **Linux x86-64** command-line-tools shard URLs matching the target API (community mirror or Huawei official).
2. Run this repo's **Build CI image** workflow (`workflow_dispatch`):
   - `image_tag`: target tag (must be in the "validate tag" step's known list)
   - `clt_zip_url`: shard URLs, space-separated (optionally append a `.sha256` verification URL)
   - `clt_version`: version string (used for the release note and the OCI version label)
3. On success a same-named formal Release is published as the build announcement and the image is
   pushed to `ghcr.io/dalongzhuazi/harmonyos-ci:<tag>`.

When adding a tag, update all three places: the workflow's **validate** list, the workflow's
**description** case, and the image tables in the root `README.md` and `docker/README.md`.

> `GHCR_PAT`: because the package was first created by the NGF repo, writing the same-named package
> from another repo is `deny(write_package)` - hence the workflow logs in with a user-level PAT
> (scope `write:packages` at minimum) rather than the repo-scoped `GITHUB_TOKEN`.
