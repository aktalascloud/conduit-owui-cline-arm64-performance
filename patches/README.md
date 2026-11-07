# Applied downstream patches: conduit

Only currently applied maintainer differences from the exact official baseline are included.
Содержит только текущие применённые нами отличия от указанного официального upstream.
Mainstream-only commits, rejected proposals and reverted experiments are excluded.
Коммиты самого mainstream, неприменённые предложения и отменённые эксперименты исключены.

Official baseline: `5d8c74ef44e2e1f324c09e35463ca170dad75849`. Downstream snapshot: `fb24e0ddafea83289e128ae239115d4a5d594404`.
Patches are already applied in this fork. Apply `series` only to a clean checkout of that exact baseline.
В этом форке патчи уже применены. `series` предназначен только для чистого checkout указанной базы.
Files are grouped by purpose; manifest.json records paths, hashes and the exact reconstructed tree.

Native Cline with pinned bounded SSH transport, account-isolated VRM/cache/call controls, compatible provider and persistence adaptations, permanent signed ARM64 packaging.

| Patch | Description | Files |
|---|---|---|
| [01-runtime.patch](01-runtime.patch) | Local runtime, integration, security, dependency and platform adaptations / Наши изменения работы, интеграций, безопасности и платформ. | 84 |
| [02-build.patch](02-build.patch) | Our reproducible build, toolchain and CI recipes / Наши сборочные рецепты, toolchain и CI. | 26 |
| [03-tests.patch](03-tests.patch) | Our regressions and adaptations of upstream fixtures / Наши регрессии и адаптации тестов. | 39 |
| [04-documentation.patch](04-documentation.patch) | Our fork documentation, notices and qualification evidence / Наши описания форка, уведомления и доказательства квалификации. | 9 |
