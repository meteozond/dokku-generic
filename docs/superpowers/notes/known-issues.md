# Known issues / minor cleanups

Список накопленных замечаний из ревью планов. Не блокеры, но стоит подобрать когда руки дойдут.

## Plan 0 — инфраструктура

- [ ] **`.actrc` Ubuntu version mismatch.** Файл объявляет runner `ubuntu-22.04`, а CI workflow в Plan 8 будет использовать `ubuntu-24.04`. Если matrix expand расходится с актом — будут расходиться окружения локально и в CI. Подровнять до `ubuntu-24.04` (image `act-24.04`) когда CI workflow лендится в Plan 8. Файл: `.actrc`.

- [ ] **`setup-dokku` отсутствует в `make help`.** Цель `setup-dokku` объявлена в `.PHONY` и работает, но `make help` её не упоминает. Разработчик не узнает о ней без чтения Makefile. Файл: `Makefile`.

- [ ] **`update` symlink перетягивает ambassador/busybox images каждый плагин-апгрейд.** `install` идемпотентен и `image inspect` skip'ает если есть, так что overhead — один `inspect` per image. Не баг, просто заметка. Файл: `install`.

## Plan 1 — MVP

- [ ] **`subcommands/info --port` не печатает trailing newline** (другие field-флаги печатают). `IP=$(dokku generic:info svc --port)` работает чисто, но `dokku generic:info svc --port; echo done` выглядит странно. Файл: `subcommands/info`. Сделать `--port` симметричным остальным.

- [ ] **`subcommands/exists` парсит аргументы напрямую через `$2`**, тогда как `destroy`/`info`/`config`/`create` используют `shift`. Унифицировать на `shift` + позиционный парсинг. Файл: `subcommands/exists`.

- [ ] **`destroy` молча игнорирует ошибку удаления volume/network** (`|| true`). Если volume занят (другой контейнер использует), пользователь не увидит warning'а. Логировать хотя бы verbose-сообщение. Файл: `subcommands/destroy:60-66`.

- [ ] **`subcommands/list` использует имя `local_image`** для script-level переменной (без `local`-keyword вне функции). Не баг, но читается странно — переименовать в `image_value` или подобное. Файл: `subcommands/list`.

- [ ] **`service_default_volume_name` определён и юнит-тестирован, но не используется**. `build_run_args` эмиттит `-v` только для записей в MOUNTS, дефолтный volume не добавляет. Решить: либо удалить хелпер, либо проводить дефолтный volume через `build_run_args` когда MOUNTS пуст. Файлы: `common-functions`, `functions`.

- [ ] **`env_set`/`env_get`/`env_unset` grep-regex hazard.** Helper'ы используют `grep -v "^${key}="` без escape — если key содержит regex-метасимволы (`.`, `*`, `[`, `\`), `env_set FILE "A.B" 1` после `env_set FILE AXB 2` молча затрёт `AXB`. На практике все callers валидируют key через `^[A-Z_][A-Z0-9_]*$` (никаких метасимволов), так что не воспроизводится. Помечено как future-proofing — можно перейти на `grep -F` (fixed-string) или escape ключа. Файл: `common-functions:42,49`.

- [ ] **`verify_service_name` нет теста на `_underscore` (rejected) и одиночную букву (`Z`, accepted).** Покрытие через regex есть, но не названным bats-тестом. Косметика — добавит уверенности в тесте. Файл: `tests/unit_helpers.bats`.

- [x] **whitespace word-splitting в `$RUN_ARGS`/`$CMD_ARGS`** — fixed в `280af46` через global bash arrays.

- [x] **shellcheck SC2154 на `$status`/`$output` в test_helper.bash** — flagged как Important но reviewer всё равно APPROVED. Проверить если CI shellcheck job ещё ругается — добавить `# shellcheck disable=SC2154` локально.

## Plan 2 — Config (set/unset/upgrade)

- [ ] **`set --mount` не дедуплицирует.** Двойной вызов `dokku generic:set svc --mount /data` запишет `/data` в MOUNTS дважды (как и create). Решение: либо добавить дедуп в set, либо явно задокументировать что для очистки используется `unset --mount /data`. Файл: `subcommands/set`.

- [ ] **`cmd_set_help` не упоминает что env-ключи должны соответствовать `^[A-Z_][A-Z0-9_]*$`** (UPPER_SNAKE). Lowercase `--env docker_host=foo` молча отклоняется. Добавить ноту в help-text. Файл: `help-functions`.

- [ ] **Нет негативных тестов на validation** в `service_set.bats` — невалидный env key (`--env 123bad=val`) и malformed pair (`--env NOEQUALS`) не покрыты. Код это обрабатывает корректно, но без теста. Файл: `tests/service_set.bats`.

- [ ] **`set` мог бы поддерживать `--no-restart`** для скриптовых батчей где caller хочет рестартовать сам в конце. Сейчас всегда рестартует. Не критично, но удобно для CI пайплайнов. Файл: `subcommands/set`.

- [ ] **`dokku_log_info1` fallback использует префикс ` ! ` — тот же что у `dokku_log_warn`.** В production Dokku core загружает свои логгеры (info1 печатает `-----> ...`), но fallback (когда core не загружен) визуально путает info с warning. Cosmetic; влияет на вывод в host-bash при unit-тестах. Если когда-нибудь будем гонять subcommand'ы напрямую в pipeline — поправить. Файл: `common-functions`.

## Plan 3 — Runtime

- [ ] **`subcommands/stop` не проверяет существование сервиса** — для отсутствующего сервиса печатает "Stopped X" silent no-op. Несимметрично с `start`/`restart` которые делают `service_exists` guard. Добавить guard или явно задокументировать как no-op. Файл: `subcommands/stop`.

- [ ] **Нет теста на `logs -f` (follow)** — потребует backgrounding с timeout, чтобы тест не висел вечно. Когда установится `timeout`-pattern для bats — добавить. Файл: `tests/service_logs.bats`.

## Plan 4 — Linking

- [ ] **`generic:links <app>` не валидирует app**. `linked <service>` ругается на несуществующий сервис, а `links <app>` молча возвращает "(no services linked)" даже если apps:exists false. Асимметрия маскирует опечатки. Добавить `dokku apps:exists "$APP"` guard. Файл: `subcommands/links`.

- [ ] **`--alias EXPLICIT` пропускается через `service_alternative_alias` и auto-bump'ится на конфликт.** Семантика `--alias` — "use this exact prefix", но текущая реализация при коллизии превращает `--alias DATABASE` в `DATABASE2`. Тесты Plan 4 этого требуют (test "generates alternative prefix when default occupied" использует `--alias TESTPG` намеренно для bump'а). Решить — оставить как есть (документировать в help) или сделать explicit alias строгим (fail при конфликте). Файл: `subcommands/link`.

- [ ] **Plan 4 не сохраняет resolved alias в state.** `unlink`/`promote` ищут "наши" config-keys по совпадению значения с DNS-именем сервиса. Работает, но fragile если `LINK_ENV`-значения не содержат DNS. Завести `$ROOT/APPS/$APP.alias` per-app файл при link, читать при unlink/promote. Это закроет также минорный issue с `--alias`. Файлы: `subcommands/link`, `subcommands/unlink`, `subcommands/promote`.

- [ ] **`subcommands/promote` имеет dead code** (lines 60, 100): `ROOT_PREFIX` присваивается через `${OUR_PREFIX%%[0-9]*}` и сразу перезаписывается через sed; `service_alternative_alias` вызывается и результат игнорируется в пользу manual loop. Не баг, но мешает читать. Подчистить когда руки дойдут. Файл: `subcommands/promote`.

## Кросс-плановые / архитектурные

- [ ] **`tests/test_helper.bash` дублирует переменные из `config`** (PLUGIN_NETWORK_PREFIX, PLUGIN_VOLUME_PREFIX, etc.) вместо source `config`. Дрейф вероятен. Заменить на `source "$PLUGIN_BASE_PATH/config"` и убрать дубликаты. Файл: `tests/test_helper.bash`.

- [ ] **Atomic-write pattern `mktemp+mv`** дублируется в `env_set`/`env_unset` (`common-functions`) и `remove_line` (`subcommands/unset`). Plan 4 добавит ещё один сайт (LINKS update). Извлечь в общий хелпер `atomic_write_file <path> <content-via-stdin>` или подобный. Файл: `common-functions`.

- [ ] **`env_unescape` через `printf '%b'`** интерпретирует все backslash-escape-sequences (`\t`, `\xNN`, `\0NNN`), а не только `\n`/`\r`/`\\`. Если когда-нибудь в env-значениях будут литеральные `\t`, roundtrip сломается. Сейчас не баг (escape-функция эти символы не экранирует, проходят как литерал). Сменить на explicit sed-замену если расширим набор экранируемых. Файл: `common-functions`.

- [ ] **`--config-opt`** (произвольные `docker run` аргументы как одна строка) — упомянут в спеке но не реализован. Сейчас есть `--docker-arg ARG` (повторяемый) и `--cmd "..."`. Возможно `--config-opt` не нужен. Решить — удалить из спеки или реализовать. Файлы: спека §3.1, `subcommands/create`.
