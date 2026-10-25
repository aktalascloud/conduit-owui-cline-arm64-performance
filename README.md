# Conduit · ARM64

[English](README.md) · [Русский](README.ru.md) · [Upstream](https://github.com/cogwheel0/conduit) · [Releases](https://github.com/aktalascloud/conduit-arm64-performance/releases/latest)

One signed ARM64 APK with extended Russian interface and MCP/workspace dialogs.

[Download APK](https://github.com/aktalascloud/conduit-arm64-performance/releases/latest/download/Conduit-arm64-v8a.apk). Permanent fork ID/signature preserve upgrades.

## Changes

- Model default filters and MCP tool images [#870](https://github.com/cogwheel0/conduit/pull/870), inline video [#869](https://github.com/cogwheel0/conduit/pull/869), late server dictation after Stop [#873](https://github.com/cogwheel0/conduit/pull/873).
- SQLite 3.53.4, Dart JNI 1.0.3 and ONNX Runtime/JNI 1.22.0: source-built ARMv8-A O3/ThinLTO.
- Dart release AOT; other vendor binaries are identified separately.
- ABI/exports, APK signature, 16 KiB ELF/ZIP alignment and native license notices are checked. [Full patch list](.avx1/PATCHES.json).

## Evidence

Previous measured APK (24 October 2026): **92,667,875 bytes**, **4.78% smaller** than official v4.2.1 ARM64. This is package size, not runtime speed. Phone performance is unmeasured. [All nine libraries, sources, flags and hashes](.avx1/measurements/native-release-316e124d.json).

No LLM weights or personal configuration. The original 2.3 MB Silero VAD detector remains bundled with its verified MIT notice.

Original licenses/notices and source history are preserved. Exact corresponding source is linked from each release. Credentials, logs, LLM weights and private filter/bridge code stay outside the public packages.
