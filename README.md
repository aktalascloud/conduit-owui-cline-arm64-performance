# Conduit OWUI + Cline ARM64

Unofficial fork with reviewed agent/MCP fixes and extended Russian UI. One latest APK.

[Upstream](https://github.com/cogwheel0/conduit) · [Release](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest) · [Patches](.avx1/PATCHES.json)

## Build

Requires Python3.12+, Git and GitHub CLI for CI. No LLM, model weights or Codex dependency.

```cmd
Build.cmd status
Build.cmd build
```

`build` verifies the clean published commit and dispatches the pinned workflow. For a prepared local compiler/SDK environment: `Build.cmd local`. Dependencies, flags, tests and license gates are in `.avx1/`; lockfiles and source history are retained. Signing keys stay outside the repository.

## Run and verify

Use the single release package. Keep user data separate from source. Settings, endpoints and model selection are runtime configuration, not build requirements. Ivy Bridge: AVX/F16C, O3 and verified LTO, without AVX2/FMA/PGO/fast-math. Android: ARM64 release AOT; source-built and prebuilt libraries are identified in the package manifest.

Current checks and measurements: [.avx1/measurements/latest.json](.avx1/measurements/latest.json). CPU microbenchmarks are not LLM tokens/s. Original licenses and notices apply.

Android native builds use Linux (the CI environment). Local builds require the same pinned SDK/NDK and private `CONDUIT_KEYSTORE_BASE64` / `CONDUIT_KEYSTORE_PASSWORD` environment variables; never commit their values.
