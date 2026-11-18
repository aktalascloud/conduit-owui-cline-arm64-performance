# Conduit · Open WebUI and Cline for Android

[Русский](#русский) · [Release / Скачать](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/tag/daily-20261118-8187e86c) · [Guide / Документация](patches/README.md) · [Evidence / Данные](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/blob/8187e86ca54799c8d6cce53a85aa481596aa8340/.avx1/measurements/onnx-qualified-reference.json) · [Upstream](https://github.com/cogwheel0/conduit)

Android ARM64 client for Open WebUI and native Cline sessions, with Russian localization, lazy session views and an optional SSH gateway. Android builds include pinned native Android libraries.

**Quick start.** Install the `arm64-v8a` APK and connect to your Open WebUI server. To build from source, use `Build.cmd status` and `Build.cmd build` with Python 3.12+, Git and GitHub CLI.

**Evidence.** The native qualification checked ONNX Runtime compilation, AArch64 exports and 16 KiB alignment in run `40821699974`. That run’s Flutter candidate failed a type check. The separate release records focused Cline transport, client and navigation checks. Phone FPS and vendor inference speed are unmeasured.

## Русский

Клиент Android ARM64 для Open WebUI и нативных сессий Cline. Есть русский интерфейс, загрузка вкладок по запросу и опциональный шлюз SSH. Версии нативных библиотек закреплены.

**Запуск.** Установите APK `arm64-v8a` и подключитесь к своему серверу Open WebUI. Для сборки выполните `Build.cmd status` и `Build.cmd build` с Python 3.12+, Git и GitHub CLI.

**Проверка.** В CI `40821699974` проверены сборка ONNX Runtime, экспорты AArch64 и выравнивание 16 КиБ. Flutter-кандидат в этом прогоне не прошёл проверку типов. В отдельном выпуске указаны целевые проверки транспорта Cline, клиента и навигации. FPS и скорость инференса на телефоне не измерялись.

[All projects / Все проекты](https://github.com/aktalascloud)
