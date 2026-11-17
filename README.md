# Conduit OWUI + Cline ARM64

[Upstream](https://github.com/cogwheel0/conduit) · [signed ARM64 APK](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest) · [Applied patches](patches/README.md)

Build with Python 3.12+, Git and GitHub CLI: `Build.cmd status`, then `Build.cmd build`. CI and checks are in `.avx1/`. Keep user data, model weights and credentials outside the source checkout.

Cline через SSH с проверкой ключа, русский интерфейс, VRM и дополнительные провайдеры. Инструкции шлюза — [remote](remote/README.md). APK проверен в CI, физический телефон проверяется отдельно.

[Checks and measurements](.avx1/measurements/latest.json)
