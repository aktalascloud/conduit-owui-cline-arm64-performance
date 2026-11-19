# Conduit OWUI ARM64

[Upstream](https://github.com/cogwheel0/conduit) · [signed ARM64 APK](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest) · [Applied patches](patches/README.md)

Build with Python 3.12+, Git and GitHub CLI. Run `Build.cmd status`, then `Build.cmd build`. CI and checks are in `.avx1/`.

Клиент Open WebUI с русским интерфейсом, голосовыми VRM и дополнительными провайдерами. ARM64 release AOT, SQLite/dartjni/ONNX с O3 и ThinLTO. Данные и ключи храните вне исходников. Подпись и ID APK сохраняются для обновления установленного приложения.

[Checks and measurements](.avx1/measurements/latest.json)
