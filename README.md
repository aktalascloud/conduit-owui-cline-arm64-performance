# Conduit OWUI + Cline ARM64

[Русский](README.ru.md)

Unofficial fork with reviewed agent/MCP fixes and extended Russian UI. One latest APK.

[Upstream](https://github.com/cogwheel0/conduit) · [Release](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest) · [Patches](.avx1/PATCHES.json)

Native Cline chat uses Conduit themes, responsive spacing and an Act-only composer. Avatar bindings refresh from the server; the private 100 MiB cache checks server SHA256 and downloads changed VRMs. Personal avatars stay on the server.

## Build

Requires Python 3.12+, Git and GitHub CLI for CI. No LLM, model weights or Codex dependency.

```cmd
Build.cmd status
Build.cmd build
```

`build` verifies the clean published commit and dispatches the pinned workflow. For a prepared local compiler/SDK environment: `Build.cmd local`. Dependencies, flags, tests and license gates are in `.avx1/`; lockfiles and source history are retained. Signing keys stay outside the repository.

## Run and verify

Install the single signed ARM64 APK. Keep user data separate from source. Android release AOT and native-library provenance/flags are recorded in the manifest. Phone FPS has not been measured.

Current checks and measurements: [.avx1/measurements/latest.json](.avx1/measurements/latest.json). CPU microbenchmarks are not LLM tokens/s. Original licenses and notices apply.

Android native builds use Linux (the CI environment). Local builds require the same pinned SDK/NDK and private `CONDUIT_KEYSTORE_BASE64` / `CONDUIT_KEYSTORE_PASSWORD` environment variables; never commit their values.
