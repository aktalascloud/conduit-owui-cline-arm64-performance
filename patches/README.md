# Applied downstream patches: conduit

Only currently applied maintainer differences from the exact official baseline are included.
Содержит только текущие применённые нами отличия от указанного официального upstream.
Mainstream-only commits, rejected proposals and reverted experiments are excluded.
Коммиты самого mainstream, неприменённые предложения и отменённые эксперименты исключены.

Official baseline: `f9655575c92297161d0099d8a5a1f0eb9525d0d2`. Downstream snapshot: `0796f5f29dcbaebbbc26b862d7ef52642d94395f`.
Patches are already applied in this fork. Apply `series` only to a clean checkout of that exact baseline.
В этом форке патчи уже применены. `series` предназначен только для чистого checkout указанной базы.
Apply the numbered patches in the order listed in `series`. Each row describes one topic.
Накладывайте патчи в порядке файла `series`. Изменения в общих файлах остаются вместе.
The manifest records each patch’s exact file list and SHA256.

Native Cline with pinned bounded SSH transport, account-isolated VRM/cache/call controls, compatible provider and persistence adaptations, permanent signed ARM64 packaging.

| Order | Patch | Description | Files |
|---:|---|---|---:|
| 1 | [01-cline-ssh-gateway.patch](01-cline-ssh-gateway.patch) | Pin SSH identity and handle reconnects, session listing and file uploads through the Windows gateway / Закрепляет идентификатор SSH, поддерживает переподключение, список сессий и загрузку файлов через Windows-шлюз. | 19 |
| 2 | [02-cline-client.patch](02-cline-client.patch) | Add native Cline client and models for messages, sessions and tool approvals / Добавляет клиент и модели Cline для сообщений, сессий и разрешений инструментов. | 8 |
| 3 | [03-cline-navigation.patch](03-cline-navigation.patch) | Add the Cline workspace route and retain sidebar search, drafts and selection / Добавляет маршрут рабочего пространства Cline и сохраняет поиск, черновики и выбор в панели. | 26 |
| 4 | [04-voice-vrm.patch](04-voice-vrm.patch) | Bind avatars to account and file identity, bound textures and cache, and adapt voice controls / Привязывает VRM к аккаунту и файлу, ограничивает текстуры и кэш и адаптирует голосовые кнопки. | 26 |
| 5 | [05-provider-compatibility.patch](05-provider-compatibility.patch) | Adapt direct-provider profiles, MiniMax transport and default-model handling / Адаптирует профили прямых провайдеров, транспорт MiniMax и выбор модели по умолчанию. | 12 |
| 6 | [06-chat-persistence.patch](06-chat-persistence.patch) | Adapt chat payloads, outbox and sync to Open WebUI persistence / Адаптирует сообщения, очередь отправки и синхронизацию к хранению Open WebUI. | 14 |
| 7 | [07-localization.patch](07-localization.patch) | Translate Cline and other fork UI labels / Переводит подписи Cline и других функций форка. | 16 |
| 8 | [08-arm64-native.patch](08-arm64-native.patch) | Qualify ARM64 native libraries, toolchains, cache and binary verification / Проверяет ARM64-библиотеки, инструменты, кэш и свойства бинарников. | 11 |
| 9 | [09-android-package.patch](09-android-package.patch) | Configure signed ARM64 Android package, manifests and Dart dependency locks / Настраивает подпись и сборку ARM64 APK, манифесты и фиксированные Dart-зависимости. | 7 |
| 10 | [10-portable-install.patch](10-portable-install.patch) | Provide portable build commands and the fork installer / Добавляет команды переносимой сборки и установщик. | 4 |
| 11 | [11-ci-build.patch](11-ci-build.patch) | Pin toolchains and package inputs, and run the fork build and publication checks / Закрепляет инструменты и входы сборки, запускает проверки пакетов и публикации. | 11 |
| 12 | [12-project-docs.patch](12-project-docs.patch) | Document fork setup, support and license terms / Описывает установку, поддержку и условия лицензирования форка. | 2 |
| 13 | [13-fork-records.patch](13-fork-records.patch) | Record fork changes, upstream reviews and qualification measurements / Хранит журнал изменений, разбор upstream и результаты проверок. | 2 |
