# Conduit · OWUI + Cline · ARM64

[English](README.md) · [Русский](README.ru.md) · [Upstream](https://github.com/cogwheel0/conduit) · [Releases](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest)

Unofficial Conduit fork for OWUI + Cline: one signed ARM64 APK with extended Russian interface and MCP/workspace dialogs.

[Download APK](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest/download/Conduit-OWUI-Cline-arm64-v8a.apk). Permanent fork ID/signature preserve upgrades.

## Remote Cline

First screen → Cline via SSH → import the private connection JSON from your PC. Native Conduit chat includes session history, project folders, model selection, streaming Markdown, tool approvals, Stop and image/document attachments. Requires separately installed Cline and the SSH gateway. [Setup and limitations](remote/README.md).

## Changes

- Model default filters and MCP tool images [#870](https://github.com/cogwheel0/conduit/pull/870), inline video [#869](https://github.com/cogwheel0/conduit/pull/869), late server dictation after Stop [#873](https://github.com/cogwheel0/conduit/pull/873).
- SQLite 3.53.4, Dart JNI 1.0.3 and ONNX Runtime/JNI 1.22.0: source-built ARMv8-A O3/ThinLTO.
- Dart release AOT; other vendor binaries are identified separately.
- ABI/exports, APK signature, 16 KiB ELF/ZIP alignment and native license notices are checked. [Full patch list](.avx1/PATCHES.json).

## Evidence

Native Cline tests cover session routing, streaming, explicit approvals, uncertain sends, attachments, large text and small screens. A read-only SSH probe loaded real Cline history without sending an agent prompt. CI checks the complete Flutter suite and pinned Cline protocol. Phone/LLM speed is unmeasured. [Last published native-library measurements](.avx1/measurements/cline-remote-793d7402.json); each release identifies its exact source and checks.

No LLM weights or personal configuration. The original 2.3 MB Silero VAD detector remains bundled with its verified MIT notice.

Original licenses/notices and source history are preserved. Exact corresponding source is linked from each release. Credentials, logs, LLM weights and private filter/bridge code stay outside the public packages.
