# Conduit · OWUI + Cline · ARM64

Cline chat: compact unified composer, inline message actions and one-row controls; existing SSH/session/approval state and global palettes are preserved.

[English](README.md) · [Русский](README.ru.md) · [Upstream](https://github.com/cogwheel0/conduit) · [Releases](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest)

Unofficial Conduit fork for OWUI + Cline: one signed ARM64 APK with extended Russian interface and MCP/workspace dialogs.

[Download APK](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest/download/Conduit-OWUI-Cline-arm64-v8a.apk). Permanent fork ID/signature preserve upgrades.

## Remote Cline

First screen → Cline via SSH → import the private connection JSON from your PC. Native Conduit chat includes session history, project folders, model selection, streaming Markdown, tool approvals, Stop and image/document attachments. Requires separately installed Cline and the SSH gateway. [Setup and limitations](remote/README.md).

## Changes

OWUI voice calls display the model’s configured VRM0/1 avatar in a local offline 3D viewport. The native call controls remain available. Standard TTS uses playback-state mouth animation; Realtime uses output levels when available. Upload avatars in OWUI model settings; personal avatars are not bundled. Cline voice is not implemented.

- Cline is a fourth primary tab alongside Chats, Notes and Terminal. Its native chat reuses Conduit controls and light/dark colors; switching keeps SSH, drafts and attachments.
- Upstream 4.2.2: trailing dictation [#893](https://github.com/cogwheel0/conduit/pull/893), model-change consent [#890](https://github.com/cogwheel0/conduit/pull/890), opt-in reasoning [#871](https://github.com/cogwheel0/conduit/pull/871), Android Back [#892](https://github.com/cogwheel0/conduit/pull/892).

- Model default filters and MCP tool images [#870](https://github.com/cogwheel0/conduit/pull/870), inline video [#869](https://github.com/cogwheel0/conduit/pull/869), late server dictation after Stop [#873](https://github.com/cogwheel0/conduit/pull/873).
- SQLite 3.53.4, Dart JNI 1.0.3 and ONNX Runtime/JNI 1.22.0: source-built ARMv8-A O3/ThinLTO.
- Dart release AOT; other vendor binaries are identified separately.
- ABI/exports, APK signature, 16 KiB ELF/ZIP alignment and native license notices are checked. [Full patch list](.avx1/PATCHES.json).

## Evidence

Verified APK: **94,790,427 bytes**. Offline VRM rendering, Standard-TTS playback-state animation and Realtime output levels are covered by targeted tests. CI passed the chat, Cline, navigation and backend-smoke suites; unchanged coverage is inherited from the qualified **5224-test baseline**. The permanent signature, nine ARM64 libraries, ABI/exports and 16 KiB alignment are verified. Phone/LLM speed is unmeasured. [Source, hashes and exact scope](.avx1/measurements/voice-avatars-b2addfde.json).

No LLM weights or personal configuration. The original 2.3 MB Silero VAD detector remains bundled with its verified MIT notice.

Original licenses/notices and source history are preserved. Exact corresponding source is linked from each release. Credentials, logs, LLM weights and private filter/bridge code stay outside the public packages.
