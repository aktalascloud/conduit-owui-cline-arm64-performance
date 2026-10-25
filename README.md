# Conduit · OWUI + Cline · ARM64

[English](README.md) · [Русский](README.ru.md) · [Upstream](https://github.com/cogwheel0/conduit) · [Releases](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest)

Unofficial Conduit fork for OWUI + Cline: one signed ARM64 APK with extended Russian interface and MCP/workspace dialogs.

[Download APK](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest/download/Conduit-OWUI-Cline-arm64-v8a.apk). Permanent fork ID/signature preserve upgrades.

## Remote Cline

First screen → Cline via SSH → import the private connection JSON from your PC. Open Cline sessions and choose the folder for new sessions; tool approvals remain enabled. Requires separately installed Cline and the SSH gateway. [Setup and limitations](remote/README.md).

## Changes

- Model default filters and MCP tool images [#870](https://github.com/cogwheel0/conduit/pull/870), inline video [#869](https://github.com/cogwheel0/conduit/pull/869), late server dictation after Stop [#873](https://github.com/cogwheel0/conduit/pull/873).
- SQLite 3.53.4, Dart JNI 1.0.3 and ONNX Runtime/JNI 1.22.0: source-built ARMv8-A O3/ThinLTO.
- Dart release AOT; other vendor binaries are identified separately.
- ABI/exports, APK signature, 16 KiB ELF/ZIP alignment and native license notices are checked. [Full patch list](.avx1/PATCHES.json).

## Evidence

Current verified APK: **94,257,855 bytes**; **5034 Flutter tests** pass. The first Android screen and Accounts include **Cline via SSH**. Image/document transfer, the pinned SSH gateway and the Cline session contract are tested. Phone/LLM speed is unmeasured. [Nine libraries, sources, actual flags and verification](.avx1/measurements/cline-remote-793d7402.json).

No LLM weights or personal configuration. The original 2.3 MB Silero VAD detector remains bundled with its verified MIT notice.

Original licenses/notices and source history are preserved. Exact corresponding source is linked from each release. Credentials, logs, LLM weights and private filter/bridge code stay outside the public packages.
