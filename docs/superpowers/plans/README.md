# dokku-generic Implementation Plans

Серия из 8 планов реализации универсального плагина Dokku. Каждый план производит работающий, тестируемый кусок функциональности.

| # | Plan | Goal | Result after completion |
|---|---|---|---|
| 1 | [MVP — skeleton + helpers + базовые subcommands](2026-05-06-dokku.generic.plan-1-mvp.md) | Каркас плагина, helper-функции с unit-тестами, `create`/`destroy`/`list`/`exists`/`info`/`config` | Можно создать сервис из любого образа, посмотреть его, удалить |
| 2 | [Config — set / unset / upgrade](2026-05-06-dokku.generic.plan-2-config.md) | Изменение конфигурации существующего сервиса теми же флагами, что и create | Можно менять image/port/env/mounts/cmd с авто-рестартом |
| 3 | [Runtime — start / stop / restart / pause / enter / exec / logs](2026-05-06-dokku.generic.plan-3-runtime.md) | Управление состоянием контейнера и доступ внутрь | Можно стопать/стартовать/входить в контейнер, выполнять команды, читать логи |
| 4 | [Linking — link / unlink / linked / links / app-links / promote](2026-05-06-dokku.generic.plan-4-linking.md) | Привязка сервисов к приложениям Dokku, автогенерация переменных, изоляция per-service сетей | Можно линковать сервис к app, в config app появляются `<PREFIX>_HOST/PORT/URL` |
| 5 | [Expose — expose / unexpose (ambassador)](2026-05-06-dokku.generic.plan-5-expose.md) | Публикация портов наружу через ambassador-контейнер | Можно открывать порты сервиса на хосте без рестарта самого сервиса |
| 6 | [Clone & Rename](2026-05-06-dokku.generic.plan-6-clone-rename.md) | Копирование сервиса (опционально с данными) и переименование с обновлением linked apps | Можно клонировать сервис, переименовывать с переносом всех связей |
| 7 | [Lifecycle Hooks](2026-05-06-dokku.generic.plan-7-hooks.md) | pre-start / pre-delete / post-app-clone-setup / post-app-rename-setup | Dokku корректно интегрируется: апы поднимают свои сервисы, удаление app чистит links |
| 8 | [CI / Release / README](2026-05-06-dokku.generic.plan-8-ci-readme.md) | GitHub Actions с матрицей версий Dokku, tagged-release, полная документация | Плагин готов к публикации и установке: `dokku plugin:install ...` |

## Спецификация

Все планы реализуют дизайн из:
[`docs/superpowers/specs/2026-05-06-dokku.generic.plugin-design.md`](../specs/2026-05-06-dokku.generic.plugin-design.md)

## Порядок выполнения

Планы должны выполняться **последовательно**. Каждый план опирается на helpers и subcommands из предыдущих:
- Plan 2 переиспользует `service_restart_internal` из Plan 1.
- Plan 4 опирается на `service_url`/`service_alias` из Plan 4 Task 1.
- Plan 5 уверен, что Plan 1's `destroy` корректно убирает ambassador-контейнеры.
- Plan 6 (rename) использует `service_alias` из Plan 4 для переписывания config-ключей.
- Plan 7 hooks вызывают subcommands из Plans 3 (start) и 4 (link/unlink).

## Как выполнять

Для каждого плана выбрать один из подходов:

1. **Subagent-Driven** (skill `superpowers:subagent-driven-development`) — отдельный subagent на каждую задачу, ревью между задачами.
2. **Inline Execution** (skill `superpowers:executing-plans`) — выполнение в текущей сессии с чекпоинтами.

## Между планами

После каждого плана:
1. Запустить полный test suite: `make test`.
2. Manual smoke (раздел "Self-Review" / "smoke" в плане).
3. Создать промежуточный тэг (опционально): `git tag plan-N-done`.
4. Перейти к следующему плану.
