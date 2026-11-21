# Applied downstream patches: conduit

Only currently applied maintainer differences from the exact official baseline are included.
Содержит только текущие применённые нами отличия от указанного официального upstream.
Mainstream-only commits, rejected proposals and reverted experiments are excluded.
Коммиты самого mainstream, неприменённые предложения и отменённые эксперименты исключены.

Official baseline: `c1372fc9eead16c5cf2f2f2d5f508fae81f2552e`. Downstream snapshot: `d8cd391b436f1bd82142335599a0a28ec0fbc592`.
Patches are already applied in this fork. Apply `series` only to a clean checkout of that exact baseline.
В этом форке патчи уже применены. `series` предназначен только для чистого checkout указанной базы.
Apply the numbered patches in the order listed in `series`. Each row describes one topic.
Накладывайте патчи в порядке файла `series`. Изменения в общих файлах остаются вместе.
The manifest records each patch’s exact file list and SHA256.

Open WebUI client with account-isolated VRM/cache/call controls, provider and persistence adaptations, permanent signed ARM64 packaging.

| Order | Patch | Description | Files |
|---:|---|---|---:|
| 1 | [01-long-chat-rendering.patch](01-long-chat-rendering.patch) | Reuse measured row heights and prepared Markdown on remount / Повторно использует высоты строк и подготовленный Markdown при прокрутке длинного чата. | 4 |
| 2 | [02-backend-navigation.patch](02-backend-navigation.patch) | Preserve normal account routing after retiring the standalone backend / Сохраняет штатный выбор аккаунта после удаления отдельного backend. | 1 |
| 3 | [03-voice-vrm.patch](03-voice-vrm.patch) | Bind avatars to account and file identity, bound textures and cache, and adapt voice controls / Привязывает VRM к аккаунту и файлу, ограничивает текстуры и кэш и адаптирует голосовые кнопки. | 22 |
| 4 | [04-provider-compatibility.patch](04-provider-compatibility.patch) | Adapt direct-provider profiles, MiniMax transport and default-model handling / Адаптирует профили прямых провайдеров, транспорт MiniMax и выбор модели по умолчанию. | 10 |
| 5 | [05-chat-persistence.patch](05-chat-persistence.patch) | Adapt chat payloads, outbox and sync to Open WebUI persistence / Адаптирует сообщения, очередь отправки и синхронизацию к хранению Open WebUI. | 11 |
| 6 | [06-localization.patch](06-localization.patch) | Translate fork UI labels / Переводит подписи интерфейса форка. | 16 |
| 7 | [07-arm64-native.patch](07-arm64-native.patch) | Qualify ARM64 native libraries, toolchains, cache and binary verification / Проверяет ARM64-библиотеки, инструменты, кэш и свойства бинарников. | 11 |
| 8 | [08-android-package.patch](08-android-package.patch) | Configure signed ARM64 Android package, manifests and Dart dependency locks / Настраивает подпись и сборку ARM64 APK, манифесты и фиксированные Dart-зависимости. | 5 |
| 9 | [09-portable-install.patch](09-portable-install.patch) | Provide portable build commands and the fork installer / Добавляет команды переносимой сборки и установщик. | 4 |
| 10 | [10-ci-build.patch](10-ci-build.patch) | Pin toolchains and package inputs, and run the fork build and publication checks / Закрепляет инструменты и входы сборки, запускает проверки пакетов и публикации. | 11 |
| 11 | [11-project-docs.patch](11-project-docs.patch) | Document fork setup, support and license terms / Описывает установку, поддержку и условия лицензирования форка. | 1 |
| 12 | [12-fork-records.patch](12-fork-records.patch) | Record fork changes, upstream reviews and qualification measurements / Хранит журнал изменений, разбор upstream и результаты проверок. | 2 |
| 13 | [13-runtime.patch](13-runtime.patch) | Local runtime, integration, security, dependency and platform adaptations / Наши изменения работы, интеграций, безопасности и платформ. | 1 |
| 14 | [14-build.patch](14-build.patch) | Our reproducible build, toolchain and CI recipes / Наши сборочные рецепты, toolchain и CI. | 1 |
