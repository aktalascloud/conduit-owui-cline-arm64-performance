# Conduit OWUI + Cline ARM64

Неофициальный форк: проверенные исправления для агентов/MCP и дополненный русский интерфейс. Один актуальный APK.

[Upstream](https://github.com/cogwheel0/conduit) · [Release](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest) · [Patches](.avx1/PATCHES.json)

## Сборка

Нужны Python3.12+, Git и GitHub CLI для CI. Сборка не зависит от модели, её весов или Codex.

```cmd
Build.cmd status
Build.cmd build
```

`build` проверяет чистоту опубликованного коммита и запускает закреплённый workflow. При готовом локальном компиляторе/SDK: `Build.cmd local`. Зависимости, флаги, тесты и проверки лицензий — в `.avx1/`. Lockfiles и история исходников сохранены. Ключи подписи в репозиторий не входят.

## Установка и проверки

Используйте единственный пакет релиза. Пользовательские данные храните отдельно от исходников. Адреса серверов и выбор моделей задаются настройками, а не требованиями сборки. Ivy Bridge: AVX/F16C, O3 и проверенный LTO, без AVX2/FMA/PGO/fast-math. Android: ARM64 release AOT; происхождение нативных библиотек указано в манифесте.

Последние проверки и замеры: [.avx1/measurements/latest.json](.avx1/measurements/latest.json). Микрозамеры CPU не означают скорость LLM. Исходные лицензии и уведомления сохранены.

Нативная сборка Android выполняется в Linux, как в CI. Для локальной сборки нужны те же закреплённые SDK/NDK и закрытые переменные `CONDUIT_KEYSTORE_BASE64` / `CONDUIT_KEYSTORE_PASSWORD`; их значения нельзя коммитить.
