# Applied downstream patches: conduit

Only currently applied maintainer differences from the exact official baseline are included.
Содержит только текущие применённые нами отличия от указанного официального upstream.
Mainstream-only commits, rejected proposals and reverted experiments are excluded.
Коммиты самого mainstream, неприменённые предложения и отменённые эксперименты исключены.

Official baseline: `c1372fc9`. Downstream snapshot: `f423f1fe20ea15ced7aadc2df3807e697550eea8`.
Patches are already applied in this fork. Apply `series` only to a clean checkout of that exact baseline.
В этом форке патчи уже применены. `series` предназначен только для чистого checkout указанной базы.
Apply the numbered patches in the order listed in `series`. Each row describes one topic.
Накладывайте патчи в порядке файла `series`. Изменения в общих файлах остаются вместе.
The manifest records each patch’s exact file list and SHA256.

Open WebUI client with account-isolated VRM/cache/call controls, provider and persistence adaptations, permanent signed ARM64 packaging.

| Order | Patch | Description | Files |
|---:|---|---|---:|
| 1 | [01-backend-navigation.patch](01-backend-navigation.patch) | Preserve normal account routing after retiring the standalone backend / Сохраняет штатный выбор аккаунта после удаления отдельного backend. | 1 |
| 2 | [02-voice-vrm.patch](02-voice-vrm.patch) | Bind avatars to account and file identity, bound textures and cache, and adapt voice controls / Привязывает VRM к аккаунту и файлу, ограничивает текстуры и кэш и адаптирует голосовые кнопки. | 22 |
| 3 | [03-provider-compatibility.patch](03-provider-compatibility.patch) | Adapt direct-provider profiles, MiniMax transport and default-model handling / Адаптирует профили прямых провайдеров, транспорт MiniMax и выбор модели по умолчанию. | 10 |
| 4 | [04-chat-persistence.patch](04-chat-persistence.patch) | Adapt chat payloads, outbox and sync to Open WebUI persistence / Адаптирует сообщения, очередь отправки и синхронизацию к хранению Open WebUI. | 11 |
| 5 | [05-localization.patch](05-localization.patch) | Translate fork UI labels / Переводит подписи интерфейса форка. | 16 |
| 6 | [06-arm64-native.patch](06-arm64-native.patch) | Qualify ARM64 native libraries, toolchains, cache and binary verification / Проверяет ARM64-библиотеки, инструменты, кэш и свойства бинарников. | 11 |
| 7 | [07-android-package.patch](07-android-package.patch) | Configure signed ARM64 Android package, manifests and Dart dependency locks / Настраивает подпись и сборку ARM64 APK, манифесты и фиксированные Dart-зависимости. | 5 |
| 8 | [08-portable-install.patch](08-portable-install.patch) | Provide portable build commands and the fork installer / Добавляет команды переносимой сборки и установщик. | 4 |
| 9 | [09-ci-build.patch](09-ci-build.patch) | Pin toolchains and package inputs, and run the fork build and publication checks / Закрепляет инструменты и входы сборки, запускает проверки пакетов и публикации. | 11 |
| 10 | [10-project-docs.patch](10-project-docs.patch) | Document fork setup, support and license terms / Описывает установку, поддержку и условия лицензирования форка. | 1 |
| 11 | [11-fork-records.patch](11-fork-records.patch) | Record fork changes, upstream reviews and qualification measurements / Хранит журнал изменений, разбор upstream и результаты проверок. | 2 |
| 12 | [12-runtime.patch](12-runtime.patch) | Local runtime, integration, security, dependency and platform adaptations / Наши изменения работы, интеграций, безопасности и платформ. | 2 |
| 13 | [13-build.patch](13-build.patch) | Our reproducible build, toolchain and CI recipes / Наши сборочные рецепты, toolchain и CI. | 1 |
