# Conduit · OWUI + Cline · ARM64

[English](README.md) · [Русский](README.ru.md) · [Исходный проект](https://github.com/cogwheel0/conduit) · [Релизы](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest)

Неофициальный форк Conduit для OWUI + Cline: один подписанный ARM64 APK с дополненным русским интерфейсом и диалогами MCP/рабочих пространств.

[Скачать APK](https://github.com/aktalascloud/conduit-owui-cline-arm64-performance/releases/latest). Постоянные ID/подпись сохраняют обновление приложения.

## Удалённый Cline

Настройки → «Удалённый Cline» → импорт закрытого JSON с ПК. Открываются сессии Cline; каталог для новых сессий задаётся отдельно. Подтверждения действий сохраняются. Нужны установленный Cline на ПК и SSH-шлюз. [Настройка и ограничения](remote/README.ru.md).

## Изменения

- Фильтры модели по умолчанию и изображения MCP [#870](https://github.com/cogwheel0/conduit/pull/870), видео в чате [#869](https://github.com/cogwheel0/conduit/pull/869), сохранение поздней транскрипции после остановки [#873](https://github.com/cogwheel0/conduit/pull/873).
- SQLite 3.53.4, Dart JNI 1.0.3 и ONNX Runtime/JNI 1.22.0: исходники, ARMv8-A O3/ThinLTO.
- Dart release AOT; остальные готовые библиотеки перечислены отдельно.
- Проверяются ABI/экспорты, подпись, выравнивание ELF/ZIP 16 КиБ и лицензии. [Все патчи](.avx1/PATCHES.json).

## Проверки и замеры

Проверенный APK — **92 995 823 байта**, на **4,45% меньше** официального v4.2.1 ARM64. Это размер пакета, не скорость. Пройдены **5029 тестов Flutter**; производительность телефона не измерена. [Девять библиотек, исходники, флаги и хеши](.avx1/measurements/native-release-b6c090d8.json).

Весов LLM и личных настроек нет. Исходный детектор Silero VAD 2,3 МБ сохранён с проверенным уведомлением MIT.

Оригинальные лицензии, уведомления и история исходников сохранены. Точные исходники указаны в релизе. Ключи, логи, модели LLM и закрытый код фильтра/бриджа в публичные пакеты не входят.
