# dokku-generic Plan 1 — MVP (Skeleton + Core Helpers + Basic Subcommands)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Реализовать каркас плагина dokku-generic с возможностью создать/удалить/посмотреть универсальный Docker-сервис. После завершения этого плана `dokku generic:create svc image:tag` поднимает контейнер, `generic:info`/`generic:config`/`generic:list`/`generic:exists` показывают его состояние, `generic:destroy` удаляет.

**Architecture:** Плагин Dokku в виде набора bash-скриптов: `commands` диспатчер → `subcommands/<name>` → helper-функции в `common-functions`/`functions`. Состояние сервиса — файлы в `/var/lib/dokku/services/generic/<service>/`. На сервис создаётся отдельная Docker network `dokku-generic-<service>`, контейнер запускается с named volume `dokku.generic.<service>`. Для unit-тестов helper-функции вынесены так, что их можно source'нуть и протестировать через bats без Dokku-окружения; интеграционные bats-тесты гоняются на реальном Dokku в Docker (см. `tests/setup-dokku.sh`).

**Tech Stack:** bash 5.x, bats-core, shellcheck, shfmt, Docker, Dokku ≥ v0.34.

**References:**
- Spec: `docs/superpowers/specs/2026-05-06-dokku-generic-plugin-design.md`
- Reference plugin: `tmp/dokku-redis/` (для паттернов helper-функций; код **не копируем целиком** — берём только структуру и переписываем под универсальный образ)

**Out of this plan** (будут в следующих планах):
- `set`/`unset`/`upgrade`, `start`/`stop`/`restart`/`pause`, `enter`/`exec`/`logs`
- `link`/`unlink`/`linked`/`links`/`app-links`/`promote`
- `expose`/`unexpose` (ambassador)
- `clone`/`rename`
- Lifecycle hooks (`pre-start`, `pre-delete`, `post-app-clone-setup`, `post-app-rename-setup`)
- CI workflows и release automation
- Полный README с MCP примерами

---

## Pre-task: Worktree

- [ ] Если работаем в команде — создать isolated worktree через skill `superpowers:using-git-worktrees`. Имя ветки: `feat/plan-1-mvp`. В solo-режиме можно работать в `main`.

---

## Task 1: Repository skeleton (plugin.toml, Makefile, .actrc, LICENSE)

**Files:**
- Create: `plugin.toml`
- Create: `Makefile`
- Create: `.actrc`
- Create: `LICENSE.txt`
- Create: `.editorconfig`
- Create: `README.md` (placeholder)
- Modify: `.gitignore` (добавить дополнительные пути)

- [ ] **Step 1: Создать `plugin.toml`**

Файл (точное содержимое):
```toml
[plugin]
description = "dokku universal docker image service plugin"
version = "0.1.0"

[plugin.config]

```

- [ ] **Step 2: Создать `.editorconfig`**

```
root = true

[*]
indent_style = space
indent_size = 2
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[Makefile]
indent_style = tab
```

- [ ] **Step 3: Создать `LICENSE.txt`**

MIT License, скопируй содержимое из `tmp/dokku-redis/LICENSE.txt`, замени строку с copyright holder'ом на `Copyright (c) 2026 dokku-generic contributors`.

- [ ] **Step 4: Создать `.actrc`**

```
-P ubuntu-24.04=catthehacker/ubuntu:act-22.04
--container-daemon-socket /var/run/docker.sock
```

- [ ] **Step 5: Создать `Makefile`**

```makefile
.PHONY: help lint shellcheck shfmt unit-tests integration-tests test setup-dokku act act-lint act-tests

help:
	@echo "Targets:"
	@echo "  lint               - shellcheck + shfmt"
	@echo "  shellcheck         - run shellcheck on all bash scripts"
	@echo "  shfmt              - run shfmt -d to check formatting"
	@echo "  unit-tests         - run bats tests/unit_*.bats"
	@echo "  integration-tests  - bring up Dokku in Docker, run bats tests"
	@echo "  test               - lint + unit-tests + integration-tests"
	@echo "  act-lint           - run lint job through act"
	@echo "  act-tests          - run tests job through act"
	@echo "  act                - run all act jobs"

SCRIPTS := commands install update config $(wildcard subcommands/*) common-functions functions help-functions service-list pre-start pre-delete post-app-clone-setup post-app-rename-setup

shellcheck:
	@for f in $(SCRIPTS); do [ -e "$$f" ] && shellcheck -x "$$f" || true; done

shfmt:
	shfmt -d -i 2 -ci $(SCRIPTS)

lint: shellcheck shfmt

unit-tests:
	bats tests/unit_*.bats

setup-dokku:
	./tests/setup-dokku.sh

integration-tests: setup-dokku
	bats tests/service_*.bats

test: lint unit-tests integration-tests

act-lint:
	act -j lint --privileged --bind

act-tests:
	act -j tests --privileged --bind

act: act-lint act-tests
```

- [ ] **Step 6: Обновить `.gitignore`**

Добавить (если ещё нет) после существующих строк:
```
node_modules/
*.log
test-results/
.DS_Store
```

- [ ] **Step 7: Создать README.md placeholder**

```markdown
# dokku-generic

Universal Docker image service plugin for [Dokku](https://dokku.com).

> Работает в разработке. Полная документация появится после Plan 8.

## Status

MVP. Реализовано: `generic:create / generic:destroy / generic:list / generic:exists / generic:info / generic:config`.

Spec: [`docs/superpowers/specs/2026-05-06-dokku-generic-plugin-design.md`](docs/superpowers/specs/2026-05-06-dokku-generic-plugin-design.md).

## License

MIT — see [LICENSE.txt](LICENSE.txt).
```

- [ ] **Step 8: Verify and commit**

```bash
ls -la plugin.toml Makefile .actrc LICENSE.txt .editorconfig README.md
git add plugin.toml Makefile .actrc LICENSE.txt .editorconfig README.md .gitignore
git commit -m "feat: repository skeleton (plugin.toml, Makefile, .actrc, LICENSE)"
```
Expected: один новый коммит, `git status` чист.

---

## Task 2: Plugin config (env defaults)

**Files:**
- Create: `config`

- [ ] **Step 1: Создать `config`**

Файл `config` (это shell script, source'ится из других scripts):

```bash
#!/usr/bin/env bash
[[ " redis " == *" $0 "* ]] && return 0 # avoid sourcing twice

export PLUGIN_COMMAND_PREFIX="generic"
export PLUGIN_SERVICE="generic"
export PLUGIN_DATA_HOST_ROOT="/var/lib/dokku/services/$PLUGIN_SERVICE"
export PLUGIN_DATA_ROOT="$PLUGIN_DATA_HOST_ROOT"
export PLUGIN_AMBASSADOR_IMAGE="${PLUGIN_AMBASSADOR_IMAGE:-dokku/ambassador:0.8.2}"
export PLUGIN_BUSYBOX_IMAGE="${PLUGIN_BUSYBOX_IMAGE:-busybox:1.36}"
export PLUGIN_NETWORK_PREFIX="dokku-generic"
export PLUGIN_CONTAINER_PREFIX="dokku-generic"
export PLUGIN_VOLUME_PREFIX="dokku.generic"
export PLUGIN_STOP_TIMEOUT="${PLUGIN_STOP_TIMEOUT:-10}"

export DOCKER_BIN="${DOCKER_BIN:-docker}"
```

- [ ] **Step 2: Make executable & verify**

```bash
chmod +x config
bash -c 'source ./config; echo "$PLUGIN_COMMAND_PREFIX $PLUGIN_NETWORK_PREFIX $PLUGIN_AMBASSADOR_IMAGE"'
```
Expected output: `generic dokku-generic dokku/ambassador:0.8.2`

- [ ] **Step 3: Commit**

```bash
git add config
git commit -m "feat: plugin config with env defaults"
```

---

## Task 3: Install/Update scripts (idempotent setup)

**Files:**
- Create: `install`
- Create: `update` (symlink to `install`)

- [ ] **Step 1: Создать `install`**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config"

mkdir -p "$PLUGIN_DATA_HOST_ROOT"
chown dokku:dokku "$PLUGIN_DATA_HOST_ROOT" 2>/dev/null || true

if ! "$DOCKER_BIN" image inspect "$PLUGIN_AMBASSADOR_IMAGE" >/dev/null 2>&1; then
  "$DOCKER_BIN" image pull "$PLUGIN_AMBASSADOR_IMAGE" >/dev/null
fi

if ! "$DOCKER_BIN" image inspect "$PLUGIN_BUSYBOX_IMAGE" >/dev/null 2>&1; then
  "$DOCKER_BIN" image pull "$PLUGIN_BUSYBOX_IMAGE" >/dev/null
fi

echo "dokku-generic plugin installed"
```

- [ ] **Step 2: Сделать executable и создать symlink**

```bash
chmod +x install
ln -sf install update
ls -la install update
```
Expected: `update -> install`, `install` имеет permission `-rwxr-xr-x`.

- [ ] **Step 3: Verify idempotent**

```bash
bash -n ./install      # syntax check
```
Expected: no output (exit 0).

- [ ] **Step 4: Commit**

```bash
git add install update
git commit -m "feat: install script with idempotent ambassador/busybox pull"
```

---

## Task 4: Bats test scaffolding (`test_helper.bash`)

**Files:**
- Create: `tests/test_helper.bash`

- [ ] **Step 1: Создать `tests/test_helper.bash`**

Это generic-ассерт хелпер для всех bats тестов. Скопируй паттерн из `tmp/dokku-redis/tests/test_helper.bash`, но переписать чтобы не зависел от redis-специфики:

```bash
#!/usr/bin/env bash

export PLUGIN_COMMAND_PREFIX="generic"
export PLUGIN_SERVICE="generic"
export PLUGIN_DATA_HOST_ROOT="/var/lib/dokku/services/generic"
export PLUGIN_BASE_PATH="${PLUGIN_BASE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export PLUGIN_NETWORK_PREFIX="dokku-generic"
export PLUGIN_CONTAINER_PREFIX="dokku-generic"
export PLUGIN_VOLUME_PREFIX="dokku.generic"

flunk() {
  { if [ "$#" -eq 0 ]; then cat -; else echo "$@"; fi; } | sed "s:${TMPDIR}:\$TMPDIR/:g" >&2
  return 1
}

assert_equal() {
  if [ "$1" != "$2" ]; then
    {
      echo "expected: $1"
      echo "actual:   $2"
    } | flunk
  fi
}

assert_contains() {
  if [[ "$1" != *"$2"* ]]; then
    {
      echo "expected to contain: $2"
      echo "actual:              $1"
    } | flunk
  fi
}

assert_not_contains() {
  if [[ "$1" == *"$2"* ]]; then
    {
      echo "expected NOT to contain: $2"
      echo "actual:                  $1"
    } | flunk
  fi
}

assert_success() {
  if [ "$status" -ne 0 ]; then
    flunk "command failed with exit status $status: $output"
  fi
}

assert_failure() {
  if [ "$status" -eq 0 ]; then
    flunk "expected failed exit status, got 0: $output"
  fi
  if [ "$#" -gt 0 ]; then
    assert_contains "$output" "$1"
  fi
}

assert_output() {
  local expected="$1"
  if [ "$expected" != "$output" ]; then
    {
      echo "expected: $expected"
      echo "actual:   $output"
    } | flunk
  fi
}

source_plugin() {
  source "$PLUGIN_BASE_PATH/config"
  source "$PLUGIN_BASE_PATH/common-functions"
  source "$PLUGIN_BASE_PATH/functions"
}
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n tests/test_helper.bash
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add tests/test_helper.bash
git commit -m "test: bats test_helper.bash with assert_* helpers"
```

---

## Task 5: Helper `verify_service_name` (regex `^[a-zA-Z][a-zA-Z0-9_-]*$`, length 1–50)

**Files:**
- Create: `common-functions` (минимальный stub)
- Create: `functions` (минимальный stub)
- Create: `tests/unit_helpers.bats`
- Modify: `common-functions` (добавить функцию)

- [ ] **Step 1: Создать пустые `common-functions` и `functions`**

```bash
cat > common-functions <<'EOF'
#!/usr/bin/env bash
# common-functions: helper functions used across subcommands.
EOF

cat > functions <<'EOF'
#!/usr/bin/env bash
# functions: plugin-specific helpers.
EOF

chmod +x common-functions functions
```

- [ ] **Step 2: Создать failing test `tests/unit_helpers.bats`**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  source_plugin
}

@test "verify_service_name accepts simple alphanumeric" {
  run verify_service_name "myservice"
  assert_success
}

@test "verify_service_name accepts hyphens and underscores" {
  run verify_service_name "my-service_2"
  assert_success
}

@test "verify_service_name rejects empty" {
  run verify_service_name ""
  assert_failure
}

@test "verify_service_name rejects starting with digit" {
  run verify_service_name "1service"
  assert_failure
}

@test "verify_service_name rejects starting with hyphen" {
  run verify_service_name "-service"
  assert_failure
}

@test "verify_service_name rejects dot" {
  run verify_service_name "my.service"
  assert_failure
}

@test "verify_service_name rejects names longer than 50 chars" {
  run verify_service_name "$(printf 'a%.0s' {1..51})"
  assert_failure
}

@test "verify_service_name accepts 50 chars" {
  run verify_service_name "$(printf 'a%.0s' {1..50})"
  assert_success
}
```

- [ ] **Step 3: Run test, expect failure**

```bash
bats tests/unit_helpers.bats
```
Expected: 8 tests run, all fail (`verify_service_name: command not found` или подобное).

- [ ] **Step 4: Реализовать `verify_service_name` в `common-functions`**

Добавить в конец `common-functions`:
```bash

verify_service_name() {
  local SERVICE="$1"
  if [[ -z "$SERVICE" ]]; then
    return 1
  fi
  if [[ ${#SERVICE} -gt 50 ]]; then
    return 1
  fi
  if [[ ! "$SERVICE" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
    return 1
  fi
  return 0
}
```

- [ ] **Step 5: Run tests, expect pass**

```bash
bats tests/unit_helpers.bats
```
Expected: 8 tests pass.

- [ ] **Step 6: Commit**

```bash
git add common-functions functions tests/unit_helpers.bats
git commit -m "feat: verify_service_name with bats unit tests"
```

---

## Task 6: Helper `env_escape` / `env_unescape`

**Files:**
- Modify: `common-functions`
- Modify: `tests/unit_helpers.bats`

- [ ] **Step 1: Добавить failing tests в `tests/unit_helpers.bats`**

В конец файла:
```bash

@test "env_escape escapes backslash" {
  run env_escape 'a\b'
  assert_output 'a\\b'
}

@test "env_escape escapes newline to literal \\n" {
  run env_escape $'line1\nline2'
  assert_output 'line1\nline2'
}

@test "env_escape escapes carriage return" {
  run env_escape $'a\rb'
  assert_output 'a\rb'
}

@test "env_escape passes through plain text" {
  run env_escape 'hello world!@#=:/'
  assert_output 'hello world!@#=:/'
}

@test "env_unescape decodes \\n to newline" {
  run env_unescape 'line1\nline2'
  assert_output $'line1\nline2'
}

@test "env_unescape decodes \\\\ to single backslash" {
  run env_unescape 'a\\b'
  assert_output 'a\b'
}

@test "env_escape then env_unescape is identity" {
  local input=$'line1\nline2\\\rwith=eq'
  local escaped
  escaped=$(env_escape "$input")
  run env_unescape "$escaped"
  assert_output "$input"
}
```

- [ ] **Step 2: Run, expect failure**

```bash
bats tests/unit_helpers.bats
```
Expected: новые 7 тестов fail.

- [ ] **Step 3: Реализовать в `common-functions`**

Добавить:
```bash

env_escape() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//$'\n'/\\n}"
  v="${v//$'\r'/\\r}"
  printf '%s' "$v"
}

env_unescape() {
  printf '%b' "$1"
}
```

Note: `printf '%b'` интерпретирует `\\` как `\`, `\n` как newline, `\r` как CR, что точно соответствует обратной операции к `env_escape`.

- [ ] **Step 4: Run, expect pass**

```bash
bats tests/unit_helpers.bats
```
Expected: 15 tests pass total.

- [ ] **Step 5: Commit**

```bash
git add common-functions tests/unit_helpers.bats
git commit -m "feat: env_escape/env_unescape with roundtrip test"
```

---

## Task 7: Helpers `env_set` / `env_get` / `env_unset`

**Files:**
- Modify: `common-functions`
- Modify: `tests/unit_helpers.bats`

- [ ] **Step 1: Добавить failing tests**

В конец `tests/unit_helpers.bats`:
```bash

@test "env_set creates ENV file with key=value" {
  local tmp
  tmp=$(mktemp -d)
  env_set "$tmp/ENV" "FOO" "bar"
  run cat "$tmp/ENV"
  assert_output "FOO=bar"
  rm -rf "$tmp"
}

@test "env_set updates existing key" {
  local tmp
  tmp=$(mktemp -d)
  env_set "$tmp/ENV" "FOO" "bar"
  env_set "$tmp/ENV" "FOO" "baz"
  run cat "$tmp/ENV"
  assert_output "FOO=baz"
  rm -rf "$tmp"
}

@test "env_set escapes newlines in value" {
  local tmp
  tmp=$(mktemp -d)
  env_set "$tmp/ENV" "FOO" $'line1\nline2'
  run cat "$tmp/ENV"
  assert_output 'FOO=line1\nline2'
  rm -rf "$tmp"
}

@test "env_set preserves other keys when updating" {
  local tmp
  tmp=$(mktemp -d)
  env_set "$tmp/ENV" "A" "1"
  env_set "$tmp/ENV" "B" "2"
  env_set "$tmp/ENV" "A" "11"
  run cat "$tmp/ENV"
  assert_contains "$output" "A=11"
  assert_contains "$output" "B=2"
  rm -rf "$tmp"
}

@test "env_get returns unescaped value" {
  local tmp
  tmp=$(mktemp -d)
  env_set "$tmp/ENV" "FOO" $'a\nb'
  run env_get "$tmp/ENV" "FOO"
  assert_output $'a\nb'
  rm -rf "$tmp"
}

@test "env_get returns empty on missing key" {
  local tmp
  tmp=$(mktemp -d)
  echo "OTHER=value" > "$tmp/ENV"
  run env_get "$tmp/ENV" "MISSING"
  assert_success
  assert_output ""
  rm -rf "$tmp"
}

@test "env_unset removes key" {
  local tmp
  tmp=$(mktemp -d)
  env_set "$tmp/ENV" "A" "1"
  env_set "$tmp/ENV" "B" "2"
  env_unset "$tmp/ENV" "A"
  run cat "$tmp/ENV"
  assert_output "B=2"
  rm -rf "$tmp"
}

@test "env_unset is no-op when key absent" {
  local tmp
  tmp=$(mktemp -d)
  env_set "$tmp/ENV" "A" "1"
  run env_unset "$tmp/ENV" "MISSING"
  assert_success
  run cat "$tmp/ENV"
  assert_output "A=1"
  rm -rf "$tmp"
}
```

- [ ] **Step 2: Run, expect failure**

```bash
bats tests/unit_helpers.bats
```
Expected: 8 new tests fail.

- [ ] **Step 3: Реализовать helpers**

В `common-functions` добавить:
```bash

env_set() {
  local file="$1" key="$2" value="$3"
  local dir
  dir="$(dirname "$file")"
  mkdir -p "$dir"
  local tmp
  tmp="$(mktemp "$dir/.env.XXXXXX")"
  if [[ -f "$file" ]]; then
    grep -v "^${key}=" "$file" > "$tmp" || true
  fi
  printf '%s=%s\n' "$key" "$(env_escape "$value")" >> "$tmp"
  mv "$tmp" "$file"
}

env_get() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  local line
  line=$(grep "^${key}=" "$file" | head -n1)
  [[ -z "$line" ]] && return 0
  env_unescape "${line#${key}=}"
}

env_unset() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  local dir
  dir="$(dirname "$file")"
  local tmp
  tmp="$(mktemp "$dir/.env.XXXXXX")"
  grep -v "^${key}=" "$file" > "$tmp" || true
  mv "$tmp" "$file"
}
```

- [ ] **Step 4: Run, expect pass**

```bash
bats tests/unit_helpers.bats
```
Expected: 23 tests pass total.

- [ ] **Step 5: Commit**

```bash
git add common-functions tests/unit_helpers.bats
git commit -m "feat: env_set/env_get/env_unset with atomic writes"
```

---

## Task 8: Helper `env_to_docker_args` and `env_list`

**Files:**
- Modify: `common-functions`
- Modify: `tests/unit_helpers.bats`

- [ ] **Step 1: Добавить failing tests**

В конец `tests/unit_helpers.bats`:
```bash

@test "env_list outputs all key=value pairs" {
  local tmp
  tmp=$(mktemp -d)
  env_set "$tmp/ENV" "A" "1"
  env_set "$tmp/ENV" "B" "two"
  run env_list "$tmp/ENV"
  assert_contains "$output" "A=1"
  assert_contains "$output" "B=two"
  rm -rf "$tmp"
}

@test "env_list outputs empty for missing file" {
  run env_list "/nonexistent/ENV"
  assert_success
  assert_output ""
}

@test "env_to_docker_args produces -e KEY=VALUE pairs" {
  local tmp
  tmp=$(mktemp -d)
  env_set "$tmp/ENV" "FOO" "bar"
  env_set "$tmp/ENV" "BAZ" "qux"
  run env_to_docker_args "$tmp/ENV"
  assert_contains "$output" "-e FOO=bar"
  assert_contains "$output" "-e BAZ=qux"
  rm -rf "$tmp"
}

@test "env_to_docker_args unescapes values" {
  local tmp
  tmp=$(mktemp -d)
  env_set "$tmp/ENV" "MULTILINE" $'line1\nline2'
  run env_to_docker_args "$tmp/ENV"
  assert_contains "$output" $'-e MULTILINE=line1\nline2'
  rm -rf "$tmp"
}

@test "env_to_docker_args is empty for missing file" {
  run env_to_docker_args "/nonexistent/ENV"
  assert_success
  assert_output ""
}
```

- [ ] **Step 2: Run, expect failure**

```bash
bats tests/unit_helpers.bats
```
Expected: 5 new fail.

- [ ] **Step 3: Реализовать**

В `common-functions`:
```bash

env_list() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  cat "$file"
}

env_to_docker_args() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line key val
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    printf -- '-e %s=%s ' "$key" "$(env_unescape "$val")"
  done < "$file"
}
```

- [ ] **Step 4: Run, expect pass**

```bash
bats tests/unit_helpers.bats
```
Expected: 28 tests pass.

- [ ] **Step 5: Commit**

```bash
git add common-functions tests/unit_helpers.bats
git commit -m "feat: env_list and env_to_docker_args helpers"
```

---

## Task 9: Helper `parse_mount_spec` and `mount_volume_name`

**Goal:** парсить `--mount SPEC` и генерировать имя named volume для случая, когда в spec указан только container path.

**Files:**
- Modify: `common-functions`
- Modify: `tests/unit_helpers.bats`

- [ ] **Step 1: Добавить failing tests**

```bash

@test "parse_mount_spec returns container_path only when spec is plain path" {
  run parse_mount_spec "/var/lib/data"
  assert_success
  assert_output "named||/var/lib/data|rw"
}

@test "parse_mount_spec parses host:container as bind" {
  run parse_mount_spec "/host/path:/container/path"
  assert_success
  assert_output "bind|/host/path|/container/path|rw"
}

@test "parse_mount_spec parses name:container as named with custom name" {
  run parse_mount_spec "myvol:/container/path"
  assert_success
  assert_output "named|myvol|/container/path|rw"
}

@test "parse_mount_spec accepts :ro suffix" {
  run parse_mount_spec "/host:/container:ro"
  assert_success
  assert_output "bind|/host|/container|ro"
}

@test "parse_mount_spec accepts :rw suffix" {
  run parse_mount_spec "/host:/container:rw"
  assert_success
  assert_output "bind|/host|/container|rw"
}

@test "parse_mount_spec rejects empty" {
  run parse_mount_spec ""
  assert_failure
}

@test "parse_mount_spec rejects spec without leading slash and without colon" {
  run parse_mount_spec "notapath"
  assert_failure
}

@test "mount_volume_name produces stable sha1-based name for plain path" {
  local n1 n2
  n1=$(mount_volume_name "myservice" "/var/lib/data")
  n2=$(mount_volume_name "myservice" "/var/lib/data")
  [[ "$n1" == "$n2" ]] || flunk "expected stable name, got $n1 != $n2"
  [[ "$n1" =~ ^dokku\.generic\.myservice\.[a-f0-9]{12}$ ]] || flunk "unexpected format: $n1"
}

@test "mount_volume_name differs for different paths" {
  local n1 n2
  n1=$(mount_volume_name "myservice" "/var/lib/data")
  n2=$(mount_volume_name "myservice" "/etc/conf")
  [[ "$n1" != "$n2" ]] || flunk "expected different, both got $n1"
}
```

- [ ] **Step 2: Run, expect failure**

```bash
bats tests/unit_helpers.bats
```
Expected: 9 new fail.

- [ ] **Step 3: Реализовать в `common-functions`**

```bash

# parse_mount_spec: returns "TYPE|SOURCE|TARGET|MODE"
#   TYPE: bind | named
#   SOURCE: host path (bind), volume name (named with explicit), or empty (named auto)
#   TARGET: container path
#   MODE: rw (default) or ro
parse_mount_spec() {
  local spec="$1"
  [[ -z "$spec" ]] && return 1

  local mode="rw"
  if [[ "$spec" == *:ro ]]; then
    mode="ro"
    spec="${spec%:ro}"
  elif [[ "$spec" == *:rw ]]; then
    mode="rw"
    spec="${spec%:rw}"
  fi

  if [[ "$spec" != *:* ]]; then
    # plain "/container/path" — must start with /
    [[ "$spec" == /* ]] || return 1
    printf 'named||%s|%s' "$spec" "$mode"
    return 0
  fi

  local source="${spec%%:*}"
  local target="${spec#*:}"

  [[ -z "$target" ]] && return 1
  [[ "$target" != /* ]] && return 1

  if [[ "$source" == /* ]]; then
    printf 'bind|%s|%s|%s' "$source" "$target" "$mode"
  else
    printf 'named|%s|%s|%s' "$source" "$target" "$mode"
  fi
}

mount_volume_name() {
  local service="$1" container_path="$2"
  local hash
  hash=$(printf '%s' "$container_path" | sha1sum | cut -c1-12)
  printf '%s.%s.%s' "$PLUGIN_VOLUME_PREFIX" "$service" "$hash"
}
```

- [ ] **Step 4: Run, expect pass**

```bash
bats tests/unit_helpers.bats
```
Expected: 37 tests pass.

- [ ] **Step 5: Commit**

```bash
git add common-functions tests/unit_helpers.bats
git commit -m "feat: parse_mount_spec and mount_volume_name helpers"
```

---

## Task 10: Helper `service_exists`, `service_root`, `fn-services-list`

**Files:**
- Modify: `common-functions`
- Modify: `tests/unit_helpers.bats`

- [ ] **Step 1: Failing tests**

```bash

@test "service_root returns full path under PLUGIN_DATA_ROOT" {
  run service_root "myservice"
  assert_success
  assert_output "$PLUGIN_DATA_ROOT/myservice"
}

@test "service_exists returns 1 when no state dir" {
  PLUGIN_DATA_ROOT="$(mktemp -d)"
  run service_exists "missing"
  assert_failure
  rm -rf "$PLUGIN_DATA_ROOT"
}

@test "service_exists returns 0 when state dir present" {
  PLUGIN_DATA_ROOT="$(mktemp -d)"
  mkdir -p "$PLUGIN_DATA_ROOT/exists"
  run service_exists "exists"
  assert_success
  rm -rf "$PLUGIN_DATA_ROOT"
}

@test "fn-services-list returns nothing when no services" {
  PLUGIN_DATA_ROOT="$(mktemp -d)"
  run fn-services-list
  assert_success
  assert_output ""
  rm -rf "$PLUGIN_DATA_ROOT"
}

@test "fn-services-list returns each service name on its own line" {
  PLUGIN_DATA_ROOT="$(mktemp -d)"
  mkdir -p "$PLUGIN_DATA_ROOT/svc1"
  mkdir -p "$PLUGIN_DATA_ROOT/svc2"
  run fn-services-list
  assert_success
  assert_contains "$output" "svc1"
  assert_contains "$output" "svc2"
  rm -rf "$PLUGIN_DATA_ROOT"
}
```

- [ ] **Step 2: Run, expect failure**

```bash
bats tests/unit_helpers.bats
```

- [ ] **Step 3: Реализовать**

В `common-functions`:
```bash

service_root() {
  printf '%s/%s' "$PLUGIN_DATA_ROOT" "$1"
}

service_exists() {
  local service="$1"
  [[ -d "$(service_root "$service")" ]]
}

fn-services-list() {
  [[ -d "$PLUGIN_DATA_ROOT" ]] || return 0
  local entry
  for entry in "$PLUGIN_DATA_ROOT"/*; do
    [[ -d "$entry" ]] || continue
    basename "$entry"
  done
}
```

- [ ] **Step 4: Run, expect pass**

```bash
bats tests/unit_helpers.bats
```
Expected: 42 tests pass.

- [ ] **Step 5: Commit**

```bash
git add common-functions tests/unit_helpers.bats
git commit -m "feat: service_root, service_exists, fn-services-list helpers"
```

---

## Task 11: Helper `dokku_log_*` wrappers

**Goal:** unified logging (info/warn/fail). Использует Dokku core helpers если доступны, иначе fallback на echo. Это упрощает тестирование (можно source без Dokku).

**Files:**
- Modify: `common-functions`
- Modify: `tests/unit_helpers.bats`

- [ ] **Step 1: Failing tests**

```bash

@test "dokku_log_info1 prints message to stdout" {
  run dokku_log_info1 "hello"
  assert_success
  assert_contains "$output" "hello"
}

@test "dokku_log_warn prints to stderr" {
  run --separate-stderr dokku_log_warn "warn message"
  assert_success
  assert_contains "$stderr" "warn message"
}

@test "dokku_log_fail prints to stderr and exits 1" {
  run --separate-stderr dokku_log_fail "fail message"
  assert_failure
  assert_contains "$stderr" "fail message"
}
```

- [ ] **Step 2: Run, expect failure**

```bash
bats tests/unit_helpers.bats
```

- [ ] **Step 3: Реализовать**

В `common-functions`:
```bash

# When Dokku core is available, prefer its loggers; otherwise fallback.
if ! declare -f dokku_log_info1 >/dev/null 2>&1; then
  dokku_log_info1() { echo " !  $*"; }
  dokku_log_info2() { echo "=====> $*"; }
  dokku_log_info1_quiet() { :; }
  dokku_log_info2_quiet() { :; }
  dokku_log_verbose() { echo "       $*"; }
  dokku_log_verbose_quiet() { :; }
  dokku_log_warn() { echo " !  $*" >&2; }
  dokku_log_fail() { echo " !  $*" >&2; exit 1; }
fi
```

- [ ] **Step 4: Run, expect pass**

```bash
bats tests/unit_helpers.bats
```
Expected: 45 pass.

- [ ] **Step 5: Commit**

```bash
git add common-functions tests/unit_helpers.bats
git commit -m "feat: dokku_log_* fallback wrappers"
```

---

## Task 12: Helper `service_name` (DNS-имя контейнера) and `service_network_name`

**Files:**
- Modify: `common-functions`
- Modify: `tests/unit_helpers.bats`

- [ ] **Step 1: Failing tests**

```bash

@test "service_container_name returns dokku-generic-<svc>" {
  run service_container_name "myservice"
  assert_output "dokku-generic-myservice"
}

@test "service_network_name returns dokku-generic-<svc>" {
  run service_network_name "myservice"
  assert_output "dokku-generic-myservice"
}

@test "service_default_volume_name returns dokku.generic.<svc>" {
  run service_default_volume_name "myservice"
  assert_output "dokku.generic.myservice"
}
```

- [ ] **Step 2: Run, expect failure**

```bash
bats tests/unit_helpers.bats
```

- [ ] **Step 3: Реализовать**

В `common-functions`:
```bash

service_container_name() {
  printf '%s-%s' "$PLUGIN_CONTAINER_PREFIX" "$1"
}

service_network_name() {
  printf '%s-%s' "$PLUGIN_NETWORK_PREFIX" "$1"
}

service_default_volume_name() {
  printf '%s.%s' "$PLUGIN_VOLUME_PREFIX" "$1"
}
```

- [ ] **Step 4: Run, expect pass**

```bash
bats tests/unit_helpers.bats
```
Expected: 48 pass.

- [ ] **Step 5: Commit**

```bash
git add common-functions tests/unit_helpers.bats
git commit -m "feat: service_container_name/network_name/default_volume_name"
```

---

## Task 13: Function `build_run_args` (state → docker run flags)

**Goal:** функция, читающая state-каталог сервиса и собирающая массив аргументов для `docker run`. Пишется в `functions` (плагин-специфичная), потому что комбинирует helper-ы из `common-functions` в полную команду.

**Files:**
- Modify: `functions`
- Modify: `tests/unit_helpers.bats`

- [ ] **Step 1: Failing tests**

```bash

@test "build_run_args includes -e flags from ENV" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  echo "redis:7" > "$tmp/myservice/IMAGE"
  env_set "$tmp/myservice/ENV" "FOO" "bar"
  run build_run_args "myservice"
  assert_success
  assert_contains "$output" "-e FOO=bar"
  rm -rf "$tmp"
}

@test "build_run_args includes -v for default volume when MOUNTS empty" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  echo "redis:7" > "$tmp/myservice/IMAGE"
  run build_run_args "myservice"
  assert_success
  # No mounts file → no -v expected; volume is created on demand at first --mount
  assert_not_contains "$output" "-v "
  rm -rf "$tmp"
}

@test "build_run_args parses MOUNTS lines into -v flags" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  echo "redis:7" > "$tmp/myservice/IMAGE"
  cat > "$tmp/myservice/MOUNTS" <<EOF
/var/lib/data
/host/path:/container/path:ro
myvol:/var/log
EOF
  run build_run_args "myservice"
  assert_success
  # plain path → named auto volume
  assert_contains "$output" "-v dokku.generic.myservice."
  assert_contains "$output" ":/var/lib/data"
  # bind mount with ro
  assert_contains "$output" "-v /host/path:/container/path:ro"
  # named with explicit name
  assert_contains "$output" "-v myvol:/var/log"
  rm -rf "$tmp"
}

@test "build_run_args includes --entrypoint when ENTRYPOINT file present" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  echo "redis:7" > "$tmp/myservice/IMAGE"
  echo "/bin/myinit" > "$tmp/myservice/ENTRYPOINT"
  run build_run_args "myservice"
  assert_success
  assert_contains "$output" "--entrypoint /bin/myinit"
  rm -rf "$tmp"
}

@test "build_run_args appends DOCKER_ARGS lines verbatim" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  echo "redis:7" > "$tmp/myservice/IMAGE"
  cat > "$tmp/myservice/DOCKER_ARGS" <<EOF
--user=1000:1000
--cap-add=NET_ADMIN
EOF
  run build_run_args "myservice"
  assert_success
  assert_contains "$output" "--user=1000:1000"
  assert_contains "$output" "--cap-add=NET_ADMIN"
  rm -rf "$tmp"
}

@test "build_cmd_args returns CMD content" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  echo "server /data --bind 0.0.0.0" > "$tmp/myservice/CMD"
  run build_cmd_args "myservice"
  assert_success
  assert_output "server /data --bind 0.0.0.0"
  rm -rf "$tmp"
}

@test "build_cmd_args returns empty when no CMD file" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  run build_cmd_args "myservice"
  assert_success
  assert_output ""
  rm -rf "$tmp"
}
```

- [ ] **Step 2: Run, expect failure**

```bash
bats tests/unit_helpers.bats
```

- [ ] **Step 3: Реализовать**

В `functions`:
```bash

# Returns space-separated string of docker run options (excluding image and CMD).
# Caller is responsible for putting together the final docker run command.
build_run_args() {
  local service="$1"
  local root
  root="$(service_root "$service")"

  # ENV → -e flags
  if [[ -f "$root/ENV" ]]; then
    env_to_docker_args "$root/ENV"
  fi

  # MOUNTS → -v flags
  if [[ -f "$root/MOUNTS" ]]; then
    local line type src tgt mode parsed
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      parsed=$(parse_mount_spec "$line") || continue
      IFS='|' read -r type src tgt mode <<< "$parsed"
      if [[ "$type" == "named" ]]; then
        if [[ -z "$src" ]]; then
          src="$(mount_volume_name "$service" "$tgt")"
        fi
        printf -- '-v %s:%s:%s ' "$src" "$tgt" "$mode"
      else
        printf -- '-v %s:%s:%s ' "$src" "$tgt" "$mode"
      fi
    done < "$root/MOUNTS"
  fi

  # ENTRYPOINT
  if [[ -s "$root/ENTRYPOINT" ]]; then
    printf -- '--entrypoint %s ' "$(<"$root/ENTRYPOINT")"
  fi

  # DOCKER_ARGS
  if [[ -f "$root/DOCKER_ARGS" ]]; then
    local arg
    while IFS= read -r arg; do
      [[ -z "$arg" ]] && continue
      printf '%s ' "$arg"
    done < "$root/DOCKER_ARGS"
  fi
}

build_cmd_args() {
  local service="$1"
  local root
  root="$(service_root "$service")"
  if [[ -s "$root/CMD" ]]; then
    cat "$root/CMD"
  fi
}
```

- [ ] **Step 4: Run, expect pass**

```bash
bats tests/unit_helpers.bats
```
Expected: 55 pass.

- [ ] **Step 5: Commit**

```bash
git add functions tests/unit_helpers.bats
git commit -m "feat: build_run_args and build_cmd_args"
```

---

## Task 14: CLI dispatcher (`commands`)

**Goal:** Точка входа плагина. Dokku вызывает `commands` с первым аргументом — именем команды (напр. `generic:create`). Скрипт диспатчит на `subcommands/create`.

**Files:**
- Create: `commands`

- [ ] **Step 1: Создать `commands`**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"
source "$PLUGIN_BASE_PATH/functions"

case "$1" in
  generic:help|generic)
    cat <<EOF
Usage: dokku generic[:COMMAND] ...

Commands:
  create       Create a new generic service
  destroy      Delete a service and its data
  exists       Check if service exists (exit 0/1)
  list         List all generic services
  info         Show service info (image, status, port, links)
  config       Show all env/link-env/mounts of service

More commands will be added in subsequent plans.
EOF
    ;;
  generic:create|generic:destroy|generic:exists|generic:list|generic:info|generic:config)
    SUBCOMMAND="${1#generic:}"
    if [[ -x "$PLUGIN_BASE_PATH/subcommands/$SUBCOMMAND" ]]; then
      "$PLUGIN_BASE_PATH/subcommands/$SUBCOMMAND" "$@"
    else
      echo " !  Subcommand $SUBCOMMAND not implemented yet" >&2
      exit 1
    fi
    ;;
  *)
    # Pass through unhandled to allow other plugins
    return 0 2>/dev/null || exit 0
    ;;
esac
```

- [ ] **Step 2: Make executable & syntax check**

```bash
chmod +x commands
bash -n commands
```
Expected: no output.

- [ ] **Step 3: Smoke test**

```bash
./commands generic:help
```
Expected: usage text printed.

- [ ] **Step 4: Commit**

```bash
git add commands
git commit -m "feat: commands CLI dispatcher"
```

---

## Task 15: `subcommands/list` and `subcommands/exists`

**Files:**
- Create: `subcommands/list`
- Create: `subcommands/exists`
- Create: `tests/service_list.bats`
- Create: `tests/service_exists.bats`

- [ ] **Step 1: Создать `tests/service_list.bats`** (failing first)

```bash
#!/usr/bin/env bats

load test_helper

@test "(generic:list) empty list when no services" {
  run dokku "$PLUGIN_COMMAND_PREFIX:list"
  assert_success
  # Either prints header or "No services" — accept any non-failure
}

@test "(generic:list) shows created services" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testlist redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:list"
  assert_success
  assert_contains "$output" "testlist"
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testlist
}
```

- [ ] **Step 2: Создать `tests/service_exists.bats`**

```bash
#!/usr/bin/env bats

load test_helper

@test "(generic:exists) exit 1 when missing" {
  run dokku "$PLUGIN_COMMAND_PREFIX:exists" doesnotexist
  assert_failure
}

@test "(generic:exists) exit 0 when present" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testexist redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:exists" testexist
  assert_success
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testexist
}
```

- [ ] **Step 3: Создать `subcommands/list`**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"
source "$PLUGIN_BASE_PATH/functions"

services=$(fn-services-list)

if [[ -z "$services" ]]; then
  dokku_log_info1 "No generic services found"
  exit 0
fi

printf '%-30s %-30s %-15s\n' "NAME" "IMAGE" "STATUS"
while IFS= read -r service; do
  [[ -z "$service" ]] && continue
  local_image=$(cat "$(service_root "$service")/IMAGE" 2>/dev/null || echo "?")
  status="unknown"
  cname="$(service_container_name "$service")"
  if "$DOCKER_BIN" container inspect "$cname" >/dev/null 2>&1; then
    status=$("$DOCKER_BIN" container inspect -f '{{.State.Status}}' "$cname")
  else
    status="not exists"
  fi
  printf '%-30s %-30s %-15s\n' "$service" "$local_image" "$status"
done <<< "$services"
```

- [ ] **Step 4: Создать `subcommands/exists`**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"

# args: $1 = "generic:exists" $2 = service
SERVICE="${2:-}"

if [[ -z "$SERVICE" ]]; then
  dokku_log_fail "Please specify a valid name for the service"
fi

if service_exists "$SERVICE"; then
  exit 0
else
  exit 1
fi
```

- [ ] **Step 5: Make executable**

```bash
mkdir -p subcommands
chmod +x subcommands/list subcommands/exists
```

- [ ] **Step 6: Run integration tests on a real Dokku** (requires Task 16 — `setup-dokku.sh`. Skip until Task 16 done; placeholder check via shellcheck)

```bash
shellcheck -x subcommands/list subcommands/exists
```
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add subcommands/list subcommands/exists tests/service_list.bats tests/service_exists.bats
git commit -m "feat: list and exists subcommands"
```

---

## Task 16: `tests/setup-dokku.sh` — Dokku in Docker for integration tests

**Goal:** запустить контейнер с установленным Dokku, смонтировать репу плагина внутрь как `/var/lib/dokku/plugins/available/generic`, активировать плагин. Используется в `make integration-tests` и в CI.

**Files:**
- Create: `tests/setup-dokku.sh`
- Create: `tests/teardown-dokku.sh`

- [ ] **Step 1: Создать `tests/setup-dokku.sh`**

```bash
#!/usr/bin/env bash
set -eo pipefail

DOKKU_TAG="${DOKKU_TAG:-v0.34.8}"
CONTAINER_NAME="dokku-generic-test"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(docker container inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)" == "running" ]]; then
  echo "Dokku already running ($CONTAINER_NAME)"
  exit 0
fi

docker container rm -f "$CONTAINER_NAME" 2>/dev/null || true

docker container run -d \
  --name "$CONTAINER_NAME" \
  --privileged \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PLUGIN_DIR":/plugin-source:ro \
  -e DOKKU_HOSTNAME=dokku.test \
  "dokku/dokku:$DOKKU_TAG"

echo "Waiting for dokku to be ready..."
for _ in $(seq 1 30); do
  if docker exec "$CONTAINER_NAME" dokku version >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Install plugin from mounted source
docker exec "$CONTAINER_NAME" bash -c '
  set -e
  rm -rf /var/lib/dokku/plugins/available/generic
  cp -r /plugin-source /var/lib/dokku/plugins/available/generic
  dokku plugin:enable generic
  dokku plugin:install-dependencies --core
'

echo "Dokku ready: $CONTAINER_NAME"
echo "Run tests with: docker exec $CONTAINER_NAME bats /var/lib/dokku/plugins/available/generic/tests/service_*.bats"
```

- [ ] **Step 2: Создать `tests/teardown-dokku.sh`**

```bash
#!/usr/bin/env bash
docker container rm -f dokku-generic-test 2>/dev/null || true
```

- [ ] **Step 3: Make executable & syntax check**

```bash
chmod +x tests/setup-dokku.sh tests/teardown-dokku.sh
bash -n tests/setup-dokku.sh tests/teardown-dokku.sh
```

- [ ] **Step 4: Smoke test (optional — пропустить если нет Docker под рукой)**

```bash
./tests/setup-dokku.sh
docker exec dokku-generic-test dokku version
docker exec dokku-generic-test dokku plugin:list | grep generic
./tests/teardown-dokku.sh
```

- [ ] **Step 5: Commit**

```bash
git add tests/setup-dokku.sh tests/teardown-dokku.sh
git commit -m "test: setup-dokku.sh to run dokku in docker for integration tests"
```

---

## Task 17: `subcommands/create` — basic happy path

**Goal:** Реализовать минимальный create — `dokku generic:create <svc> <image>` без дополнительных флагов. Создать state-каталог, network, default volume, запустить контейнер.

**Files:**
- Create: `subcommands/create`
- Create: `tests/service_create.bats`

- [ ] **Step 1: Failing tests**

`tests/service_create.bats`:
```bash
#!/usr/bin/env bats

load test_helper

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testcreate 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" service-with-dashes 2>/dev/null || true
}

@test "(generic:create) success with image" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  assert_success
  assert_contains "$output" "container created: testcreate"
}

@test "(generic:create) records image in state" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/IMAGE"
  assert_output "redis:7-alpine"
}

@test "(generic:create) creates docker network" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  run docker network inspect "dokku-generic-testcreate"
  assert_success
}

@test "(generic:create) starts running container" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  run docker container inspect -f '{{.State.Status}}' "dokku-generic-testcreate"
  assert_output "running"
}

@test "(generic:create) accepts service name with dashes" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create" service-with-dashes redis:7-alpine
  assert_success
  assert_contains "$output" "container created: service-with-dashes"
}

@test "(generic:create) error when no name" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create"
  assert_failure
  assert_contains "$output" "Please specify a valid name"
}

@test "(generic:create) error when no image" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate
  assert_failure
  assert_contains "$output" "Please specify a docker image"
}

@test "(generic:create) error when name has dot" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create" "bad.name" redis:7-alpine
  assert_failure
}

@test "(generic:create) error when service already exists" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  assert_failure
  assert_contains "$output" "already exists"
}
```

- [ ] **Step 2: Создать `subcommands/create`**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"
source "$PLUGIN_BASE_PATH/functions"

# args: $1=generic:create $2=<service> $3=<image>
SERVICE="${2:-}"
IMAGE="${3:-}"

if [[ -z "$SERVICE" ]]; then
  dokku_log_fail "Please specify a valid name for the service"
fi
if [[ -z "$IMAGE" ]]; then
  dokku_log_fail "Please specify a docker image (e.g. redis:7-alpine)"
fi
if ! verify_service_name "$SERVICE"; then
  dokku_log_fail "Invalid service name: must match ^[a-zA-Z][a-zA-Z0-9_-]*$ (max 50 chars)"
fi
if service_exists "$SERVICE"; then
  dokku_log_fail "Service $SERVICE already exists"
fi

ROOT="$(service_root "$SERVICE")"
CONTAINER="$(service_container_name "$SERVICE")"
NETWORK="$(service_network_name "$SERVICE")"

# Pull image if missing locally
if ! "$DOCKER_BIN" image inspect "$IMAGE" >/dev/null 2>&1; then
  dokku_log_info1 "Pulling image $IMAGE"
  "$DOCKER_BIN" image pull "$IMAGE"
fi

# Initialize state
mkdir -p "$ROOT"
echo "$IMAGE" > "$ROOT/IMAGE"
echo "tcp" > "$ROOT/SCHEME"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$ROOT/CREATED_AT"

cleanup_on_fail() {
  rm -rf "$ROOT"
  "$DOCKER_BIN" network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup_on_fail ERR

# Create network
"$DOCKER_BIN" network inspect "$NETWORK" >/dev/null 2>&1 \
  || "$DOCKER_BIN" network create "$NETWORK" >/dev/null

# Run container
# shellcheck disable=SC2046
"$DOCKER_BIN" container run -d \
  --name "$CONTAINER" \
  --hostname "$CONTAINER" \
  --restart unless-stopped \
  --label dokku=service \
  --label "dokku.service=$PLUGIN_SERVICE" \
  --label "dokku.generic.service=$SERVICE" \
  --network "$NETWORK" \
  --network-alias "$SERVICE" \
  $(build_run_args "$SERVICE") \
  "$IMAGE" \
  $(build_cmd_args "$SERVICE") >/dev/null

"$DOCKER_BIN" container inspect -f '{{.Id}}' "$CONTAINER" > "$ROOT/ID"
trap - ERR

dokku_log_info2 "container created: $SERVICE"
```

- [ ] **Step 3: Make executable**

```bash
chmod +x subcommands/create
```

- [ ] **Step 4: Update dispatcher to delegate `generic:create`**

`commands` уже делегирует `generic:create` → `subcommands/create` (Task 14).

- [ ] **Step 5: Run integration tests**

```bash
./tests/setup-dokku.sh
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_create.bats
./tests/teardown-dokku.sh
```
Expected: 9 tests pass.

- [ ] **Step 6: Commit**

```bash
git add subcommands/create tests/service_create.bats
git commit -m "feat: subcommands/create with basic happy path"
```

---

## Task 18: `subcommands/create` — full flag support

**Goal:** Расширить create поддержкой флагов `--port`, `--scheme`, `--env`, `--link-env`, `--mount`, `--cmd`, `--entrypoint`, `--docker-arg`, `--no-start`, `--expose`. (`--expose` пока без ambassador — отложен на Plan 5; здесь только записываем в state.)

**Files:**
- Modify: `subcommands/create`
- Modify: `tests/service_create.bats`

- [ ] **Step 1: Failing tests**

В конец `tests/service_create.bats`:
```bash

@test "(generic:create --port) records port" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --port 6379
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/PORT"
  assert_output "6379"
}

@test "(generic:create --scheme) records scheme" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --scheme redis
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/SCHEME"
  assert_output "redis"
}

@test "(generic:create --env) writes env to ENV file" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --env FOO=bar --env BAZ=qux
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/ENV"
  assert_contains "$output" "FOO=bar"
  assert_contains "$output" "BAZ=qux"
}

@test "(generic:create --link-env) writes to LINK_ENV file" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --link-env DATABASE_URL=redis://x
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/LINK_ENV"
  assert_contains "$output" "DATABASE_URL=redis://x"
}

@test "(generic:create --mount) writes to MOUNTS file" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --mount /var/lib/data --mount /host:/container:ro
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/MOUNTS"
  assert_contains "$output" "/var/lib/data"
  assert_contains "$output" "/host:/container:ro"
}

@test "(generic:create --cmd) writes CMD" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --cmd "redis-server --bind 0.0.0.0"
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/CMD"
  assert_output "redis-server --bind 0.0.0.0"
}

@test "(generic:create --entrypoint) writes ENTRYPOINT" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --entrypoint /bin/myinit
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/ENTRYPOINT"
  assert_output "/bin/myinit"
}

@test "(generic:create --docker-arg) appends to DOCKER_ARGS" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --docker-arg --user=1000 --docker-arg --cap-add=NET_ADMIN
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/DOCKER_ARGS"
  assert_contains "$output" "--user=1000"
  assert_contains "$output" "--cap-add=NET_ADMIN"
}

@test "(generic:create --no-start) creates state but no container" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --no-start
  run docker container inspect "dokku-generic-testcreate"
  assert_failure
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/IMAGE"
  assert_output "redis:7-alpine"
}

@test "(generic:create --expose) records expose for later activation" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --no-start --expose 6379:6379
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/EXPOSED_PORTS"
  assert_contains "$output" "6379:6379"
}

@test "(generic:create --env=KEY=VALUE) supports = form" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --env=FOO=bar
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/ENV"
  assert_contains "$output" "FOO=bar"
}

@test "(generic:create) container has env from --env" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --env REDIS_PASSWORD=sekret --cmd "redis-server --requirepass sekret"
  run docker exec dokku-generic-testcreate env
  assert_contains "$output" "REDIS_PASSWORD=sekret"
}
```

- [ ] **Step 2: Run, expect failure**

```bash
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_create.bats
```

- [ ] **Step 3: Переписать `subcommands/create` с парсингом флагов**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"
source "$PLUGIN_BASE_PATH/functions"

# Skip the "generic:create" prefix
shift

SERVICE=""
IMAGE=""
NO_START=0
PORT=""
SCHEME=""
CMD_OVERRIDE=""
ENTRYPOINT_OVERRIDE=""
ENV_PAIRS=()
LINK_ENV_PAIRS=()
MOUNTS=()
DOCKER_ARGS=()
EXPOSED_PORTS=()

while [[ $# -gt 0 ]]; do
  arg="$1"
  case "$arg" in
    --no-start)
      NO_START=1; shift ;;
    --port)
      PORT="$2"; shift 2 ;;
    --port=*)
      PORT="${arg#--port=}"; shift ;;
    --scheme)
      SCHEME="$2"; shift 2 ;;
    --scheme=*)
      SCHEME="${arg#--scheme=}"; shift ;;
    --env)
      ENV_PAIRS+=("$2"); shift 2 ;;
    --env=*)
      ENV_PAIRS+=("${arg#--env=}"); shift ;;
    --link-env)
      LINK_ENV_PAIRS+=("$2"); shift 2 ;;
    --link-env=*)
      LINK_ENV_PAIRS+=("${arg#--link-env=}"); shift ;;
    --mount)
      MOUNTS+=("$2"); shift 2 ;;
    --mount=*)
      MOUNTS+=("${arg#--mount=}"); shift ;;
    --cmd)
      CMD_OVERRIDE="$2"; shift 2 ;;
    --cmd=*)
      CMD_OVERRIDE="${arg#--cmd=}"; shift ;;
    --entrypoint)
      ENTRYPOINT_OVERRIDE="$2"; shift 2 ;;
    --entrypoint=*)
      ENTRYPOINT_OVERRIDE="${arg#--entrypoint=}"; shift ;;
    --docker-arg)
      DOCKER_ARGS+=("$2"); shift 2 ;;
    --docker-arg=*)
      DOCKER_ARGS+=("${arg#--docker-arg=}"); shift ;;
    --expose)
      EXPOSED_PORTS+=("$2"); shift 2 ;;
    --expose=*)
      EXPOSED_PORTS+=("${arg#--expose=}"); shift ;;
    -*)
      dokku_log_fail "Unknown flag: $arg" ;;
    *)
      if [[ -z "$SERVICE" ]]; then
        SERVICE="$arg"
      elif [[ -z "$IMAGE" ]]; then
        IMAGE="$arg"
      else
        dokku_log_fail "Unexpected positional argument: $arg"
      fi
      shift ;;
  esac
done

if [[ -z "$SERVICE" ]]; then
  dokku_log_fail "Please specify a valid name for the service"
fi
if [[ -z "$IMAGE" ]]; then
  dokku_log_fail "Please specify a docker image (e.g. redis:7-alpine)"
fi
if ! verify_service_name "$SERVICE"; then
  dokku_log_fail "Invalid service name: must match ^[a-zA-Z][a-zA-Z0-9_-]*$ (max 50 chars)"
fi
if service_exists "$SERVICE"; then
  dokku_log_fail "Service $SERVICE already exists"
fi

ROOT="$(service_root "$SERVICE")"
CONTAINER="$(service_container_name "$SERVICE")"
NETWORK="$(service_network_name "$SERVICE")"

# Pull image
if ! "$DOCKER_BIN" image inspect "$IMAGE" >/dev/null 2>&1; then
  dokku_log_info1 "Pulling image $IMAGE"
  "$DOCKER_BIN" image pull "$IMAGE"
fi

# Initialize state
mkdir -p "$ROOT"
echo "$IMAGE" > "$ROOT/IMAGE"
[[ -n "$PORT" ]] && echo "$PORT" > "$ROOT/PORT"
echo "${SCHEME:-tcp}" > "$ROOT/SCHEME"
[[ -n "$CMD_OVERRIDE" ]] && printf '%s' "$CMD_OVERRIDE" > "$ROOT/CMD"
[[ -n "$ENTRYPOINT_OVERRIDE" ]] && printf '%s' "$ENTRYPOINT_OVERRIDE" > "$ROOT/ENTRYPOINT"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$ROOT/CREATED_AT"

# Validate and write env
for pair in "${ENV_PAIRS[@]}"; do
  if [[ "$pair" != *=* ]]; then
    rm -rf "$ROOT"
    dokku_log_fail "Invalid --env, expected KEY=VALUE: $pair"
  fi
  key="${pair%%=*}"
  val="${pair#*=}"
  if [[ ! "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
    rm -rf "$ROOT"
    dokku_log_fail "Invalid --env key: $key (must match ^[A-Z_][A-Z0-9_]*$)"
  fi
  env_set "$ROOT/ENV" "$key" "$val"
done

for pair in "${LINK_ENV_PAIRS[@]}"; do
  if [[ "$pair" != *=* ]]; then
    rm -rf "$ROOT"
    dokku_log_fail "Invalid --link-env, expected KEY=VALUE: $pair"
  fi
  key="${pair%%=*}"
  val="${pair#*=}"
  if [[ ! "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
    rm -rf "$ROOT"
    dokku_log_fail "Invalid --link-env key: $key"
  fi
  env_set "$ROOT/LINK_ENV" "$key" "$val"
done

# Validate mounts and write
for spec in "${MOUNTS[@]}"; do
  if ! parse_mount_spec "$spec" >/dev/null; then
    rm -rf "$ROOT"
    dokku_log_fail "Invalid --mount spec: $spec"
  fi
  echo "$spec" >> "$ROOT/MOUNTS"
done

# Docker args
for da in "${DOCKER_ARGS[@]}"; do
  echo "$da" >> "$ROOT/DOCKER_ARGS"
done

# Exposed ports — record only; activation happens in expose subcommand (Plan 5)
for ep in "${EXPOSED_PORTS[@]}"; do
  if [[ ! "$ep" =~ ^[0-9]+:[0-9]+$ ]]; then
    rm -rf "$ROOT"
    dokku_log_fail "Invalid --expose: expected HOST:CONTAINER, got $ep"
  fi
  echo "$ep" >> "$ROOT/EXPOSED_PORTS"
done

# Stop here if --no-start
if [[ $NO_START -eq 1 ]]; then
  dokku_log_info2 "container created (not started): $SERVICE"
  exit 0
fi

cleanup_on_fail() {
  "$DOCKER_BIN" container rm -f "$CONTAINER" >/dev/null 2>&1 || true
  "$DOCKER_BIN" network rm "$NETWORK" >/dev/null 2>&1 || true
  rm -rf "$ROOT"
}
trap cleanup_on_fail ERR

# Create network
"$DOCKER_BIN" network inspect "$NETWORK" >/dev/null 2>&1 \
  || "$DOCKER_BIN" network create "$NETWORK" >/dev/null

# Build & run
RUN_ARGS=$(build_run_args "$SERVICE")
CMD_ARGS=$(build_cmd_args "$SERVICE")

# shellcheck disable=SC2046,SC2086
"$DOCKER_BIN" container run -d \
  --name "$CONTAINER" \
  --hostname "$CONTAINER" \
  --restart unless-stopped \
  --label dokku=service \
  --label "dokku.service=$PLUGIN_SERVICE" \
  --label "dokku.generic.service=$SERVICE" \
  --network "$NETWORK" \
  --network-alias "$SERVICE" \
  $RUN_ARGS \
  "$IMAGE" \
  $CMD_ARGS >/dev/null

"$DOCKER_BIN" container inspect -f '{{.Id}}' "$CONTAINER" > "$ROOT/ID"
trap - ERR

dokku_log_info2 "container created: $SERVICE"
```

- [ ] **Step 4: Run, expect pass**

```bash
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_create.bats
```
Expected: all 21 tests pass.

- [ ] **Step 5: Commit**

```bash
git add subcommands/create tests/service_create.bats
git commit -m "feat: subcommands/create with full flag support"
```

---

## Task 19: `subcommands/destroy`

**Goal:** Удалить сервис: контейнер, сеть, named volumes, state. С TTY-prompt подтверждения через ввод имени, либо `--force`/`-f`. Блочит destroy если есть активные links — но в Plan 1 LINKS не пишется, поэтому проверка делается формально (если `LINKS` пустой/отсутствует → ok).

**Files:**
- Create: `subcommands/destroy`
- Create: `tests/service_destroy.bats`
- Modify: `commands` (добавить `generic:destroy` к delegate-списку — уже добавлено в Task 14, проверить)

- [ ] **Step 1: Failing tests**

`tests/service_destroy.bats`:
```bash
#!/usr/bin/env bats

load test_helper

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testdestroy 2>/dev/null || true
}

@test "(generic:destroy) success with --force" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testdestroy redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:destroy" testdestroy --force
  assert_success
  run docker container inspect "dokku-generic-testdestroy"
  assert_failure
}

@test "(generic:destroy) removes state directory" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testdestroy redis:7-alpine
  dokku "$PLUGIN_COMMAND_PREFIX:destroy" testdestroy --force
  [[ ! -d "$PLUGIN_DATA_HOST_ROOT/testdestroy" ]]
}

@test "(generic:destroy) removes docker network" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testdestroy redis:7-alpine
  dokku "$PLUGIN_COMMAND_PREFIX:destroy" testdestroy --force
  run docker network inspect "dokku-generic-testdestroy"
  assert_failure
}

@test "(generic:destroy) removes default named volume" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testdestroy redis:7-alpine --no-start --mount /data
  dokku "$PLUGIN_COMMAND_PREFIX:destroy" testdestroy --force
  # Default and per-mount volumes should be gone
  run docker volume ls --format '{{.Name}}'
  assert_not_contains "$output" "dokku.generic.testdestroy"
}

@test "(generic:destroy) error when not exists" {
  run dokku "$PLUGIN_COMMAND_PREFIX:destroy" doesnotexist --force
  assert_failure
  assert_contains "$output" "does not exist"
}

@test "(generic:destroy) error when no name" {
  run dokku "$PLUGIN_COMMAND_PREFIX:destroy"
  assert_failure
}

@test "(generic:destroy) confirms via service name when no --force" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testdestroy redis:7-alpine
  run bash -c "echo 'wrongname' | dokku '$PLUGIN_COMMAND_PREFIX:destroy' testdestroy"
  assert_failure
  assert_contains "$output" "Confirmation did not match"
}

@test "(generic:destroy) succeeds when correct name typed" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testdestroy redis:7-alpine
  run bash -c "echo 'testdestroy' | dokku '$PLUGIN_COMMAND_PREFIX:destroy' testdestroy"
  assert_success
}
```

- [ ] **Step 2: Run, expect failure**

```bash
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_destroy.bats
```

- [ ] **Step 3: Создать `subcommands/destroy`**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"

shift  # discard "generic:destroy"

SERVICE=""
FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force) FORCE=1; shift ;;
    -*) dokku_log_fail "Unknown flag: $1" ;;
    *)
      if [[ -z "$SERVICE" ]]; then SERVICE="$1"; else dokku_log_fail "Unexpected: $1"; fi
      shift ;;
  esac
done

[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid name for the service"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name: $SERVICE"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

ROOT="$(service_root "$SERVICE")"
CONTAINER="$(service_container_name "$SERVICE")"
NETWORK="$(service_network_name "$SERVICE")"

# Block destroy if linked (Plan 4 will populate LINKS; for Plan 1 LINKS may not exist)
if [[ -s "$ROOT/LINKS" ]]; then
  dokku_log_fail "Cannot delete linked service: $(tr '\n' ' ' < "$ROOT/LINKS")"
fi

if [[ $FORCE -ne 1 ]]; then
  dokku_log_warn "WARNING: Potentially Destructive Action"
  dokku_log_warn "This command will destroy $SERVICE $PLUGIN_SERVICE service."
  dokku_log_warn "To proceed, type \"$SERVICE\""
  echo ""
  read -rp "> " confirmation
  if [[ "$confirmation" != "$SERVICE" ]]; then
    dokku_log_warn "Confirmation did not match $SERVICE. Aborted."
    exit 1
  fi
fi

dokku_log_info2_quiet "Deleting $SERVICE"

# Stop & rm container
"$DOCKER_BIN" container rm -f "$CONTAINER" >/dev/null 2>&1 || true

# Stop & rm ambassador (Plan 5 will manage; here we just clean up if exists)
"$DOCKER_BIN" container rm -f "${CONTAINER}.ambassador" >/dev/null 2>&1 || true

# Remove named volumes belonging to this service
volumes=$("$DOCKER_BIN" volume ls --format '{{.Name}}' | grep "^${PLUGIN_VOLUME_PREFIX}.${SERVICE}\(\$\|\.\)" || true)
if [[ -n "$volumes" ]]; then
  echo "$volumes" | xargs -r "$DOCKER_BIN" volume rm >/dev/null 2>&1 || true
fi

# Remove network
"$DOCKER_BIN" network rm "$NETWORK" >/dev/null 2>&1 || true

# Remove state
rm -rf "$ROOT"

dokku_log_info2 "$PLUGIN_SERVICE container deleted: $SERVICE"
```

- [ ] **Step 4: Make executable, run tests**

```bash
chmod +x subcommands/destroy
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_destroy.bats
```
Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add subcommands/destroy tests/service_destroy.bats
git commit -m "feat: subcommands/destroy with force/confirmation prompt"
```

---

## Task 20: `subcommands/info`

**Goal:** показать структурированную информацию о сервисе. Без флагов — все поля; с `--<flag>` — только указанное.

**Files:**
- Create: `subcommands/info`
- Create: `tests/service_info.bats`

- [ ] **Step 1: Failing tests**

```bash
#!/usr/bin/env bats

load test_helper

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testinfo 2>/dev/null || true
}

@test "(generic:info) shows image" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo
  assert_success
  assert_contains "$output" "Image:"
  assert_contains "$output" "redis:7-alpine"
}

@test "(generic:info) shows status running after create" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo
  assert_success
  assert_contains "$output" "Status:"
  assert_contains "$output" "running"
}

@test "(generic:info) shows status created after --no-start" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine --no-start
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo
  assert_success
  assert_contains "$output" "created"
}

@test "(generic:info) shows port when set" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine --port 6379
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo
  assert_success
  assert_contains "$output" "Port:"
  assert_contains "$output" "6379"
}

@test "(generic:info --image) prints only image" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo --image
  assert_success
  assert_output "redis:7-alpine"
}

@test "(generic:info --status) prints only status" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo --status
  assert_success
  assert_output "running"
}

@test "(generic:info --internal-ip) prints container IP in service network" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo --internal-ip
  assert_success
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || flunk "expected IP, got $output"
}

@test "(generic:info) error when not exists" {
  run dokku "$PLUGIN_COMMAND_PREFIX:info" missing
  assert_failure
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Создать `subcommands/info`**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"

shift
SERVICE=""
FLAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image|--status|--port|--internal-ip|--links|--exposed-ports)
      FLAG="$1"; shift ;;
    *)
      if [[ -z "$SERVICE" ]]; then SERVICE="$1"; else dokku_log_fail "Unexpected: $1"; fi
      shift ;;
  esac
done

[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid name for the service"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

ROOT="$(service_root "$SERVICE")"
CONTAINER="$(service_container_name "$SERVICE")"
NETWORK="$(service_network_name "$SERVICE")"

get_image() {
  cat "$ROOT/IMAGE" 2>/dev/null || echo "?"
}

get_status() {
  if "$DOCKER_BIN" container inspect "$CONTAINER" >/dev/null 2>&1; then
    "$DOCKER_BIN" container inspect -f '{{.State.Status}}' "$CONTAINER" | tr -d '\n'
  else
    if [[ -d "$ROOT" ]]; then echo -n "created"; else echo -n "not exists"; fi
  fi
}

get_port() {
  cat "$ROOT/PORT" 2>/dev/null || true
}

get_internal_ip() {
  if "$DOCKER_BIN" container inspect "$CONTAINER" >/dev/null 2>&1; then
    "$DOCKER_BIN" container inspect -f "{{(index .NetworkSettings.Networks \"$NETWORK\").IPAddress}}" "$CONTAINER" | tr -d '\n'
  fi
}

get_links() {
  [[ -f "$ROOT/LINKS" ]] && tr '\n' ' ' < "$ROOT/LINKS" || true
}

get_exposed_ports() {
  [[ -f "$ROOT/EXPOSED_PORTS" ]] && tr '\n' ' ' < "$ROOT/EXPOSED_PORTS" || true
}

case "$FLAG" in
  --image)         get_image; echo "" ;;
  --status)        get_status; echo "" ;;
  --port)          get_port ;;
  --internal-ip)   get_internal_ip; echo "" ;;
  --links)         get_links; echo "" ;;
  --exposed-ports) get_exposed_ports; echo "" ;;
  "")
    echo "=====> $SERVICE generic service information"
    printf '       %-20s %s\n' "Image:"          "$(get_image)"
    printf '       %-20s %s\n' "Status:"         "$(get_status)"
    printf '       %-20s %s\n' "Port:"           "$(get_port)"
    printf '       %-20s %s\n' "Internal IP:"    "$(get_internal_ip)"
    printf '       %-20s %s\n' "Network:"        "$NETWORK"
    printf '       %-20s %s\n' "Container:"      "$CONTAINER"
    printf '       %-20s %s\n' "Links:"          "$(get_links)"
    printf '       %-20s %s\n' "Exposed ports:"  "$(get_exposed_ports)"
    ;;
esac
```

- [ ] **Step 4: Run tests, pass**

```bash
chmod +x subcommands/info
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_info.bats
```

- [ ] **Step 5: Commit**

```bash
git add subcommands/info tests/service_info.bats
git commit -m "feat: subcommands/info with field flags"
```

---

## Task 21: `subcommands/config`

**Goal:** Печатает все ENV/LINK_ENV/MOUNTS/EXPOSED_PORTS/SCHEME/PORT секции сервиса в читабельном виде.

**Files:**
- Create: `subcommands/config`
- Create: `tests/service_config.bats`

- [ ] **Step 1: Failing tests**

```bash
#!/usr/bin/env bats

load test_helper

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testconfig 2>/dev/null || true
}

@test "(generic:config) shows env section" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testconfig redis:7-alpine --env FOO=bar --env BAZ=qux
  run dokku "$PLUGIN_COMMAND_PREFIX:config" testconfig
  assert_success
  assert_contains "$output" "FOO=bar"
  assert_contains "$output" "BAZ=qux"
}

@test "(generic:config) shows link-env section" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testconfig redis:7-alpine --link-env DATABASE_URL=postgres://x
  run dokku "$PLUGIN_COMMAND_PREFIX:config" testconfig
  assert_success
  assert_contains "$output" "DATABASE_URL=postgres://x"
}

@test "(generic:config) shows mounts" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testconfig redis:7-alpine --mount /var/data --mount /host:/container
  run dokku "$PLUGIN_COMMAND_PREFIX:config" testconfig
  assert_success
  assert_contains "$output" "/var/data"
  assert_contains "$output" "/host:/container"
}

@test "(generic:config) shows port and scheme" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testconfig redis:7-alpine --port 6379 --scheme redis
  run dokku "$PLUGIN_COMMAND_PREFIX:config" testconfig
  assert_success
  assert_contains "$output" "6379"
  assert_contains "$output" "redis"
}

@test "(generic:config) error when not exists" {
  run dokku "$PLUGIN_COMMAND_PREFIX:config" missing
  assert_failure
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Создать `subcommands/config`**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"

shift
SERVICE="${1:-}"

[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid name for the service"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

ROOT="$(service_root "$SERVICE")"

echo "=====> $SERVICE generic service configuration"

# Port & scheme
[[ -s "$ROOT/PORT"   ]] && printf '       Port:    %s\n' "$(<"$ROOT/PORT")"
[[ -s "$ROOT/SCHEME" ]] && printf '       Scheme:  %s\n' "$(<"$ROOT/SCHEME")"

# ENV
echo "       Env:"
if [[ -s "$ROOT/ENV" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "         $line"
  done < "$ROOT/ENV"
else
  echo "         (none)"
fi

# LINK_ENV
echo "       Link env:"
if [[ -s "$ROOT/LINK_ENV" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "         $line"
  done < "$ROOT/LINK_ENV"
else
  echo "         (none)"
fi

# Mounts
echo "       Mounts:"
if [[ -s "$ROOT/MOUNTS" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "         $line"
  done < "$ROOT/MOUNTS"
else
  echo "         (none)"
fi

# Exposed ports
echo "       Exposed ports:"
if [[ -s "$ROOT/EXPOSED_PORTS" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "         $line"
  done < "$ROOT/EXPOSED_PORTS"
else
  echo "         (none)"
fi
```

- [ ] **Step 4: Run, pass**

```bash
chmod +x subcommands/config
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_config.bats
```

- [ ] **Step 5: Commit**

```bash
git add subcommands/config tests/service_config.bats
git commit -m "feat: subcommands/config print"
```

---

## Task 22: Help text functions

**Goal:** Текст help для subcommand-ов, доступный через `dokku generic:help`. Минимально для команд из этого плана; в следующих планах будем расширять.

**Files:**
- Create: `help-functions`
- Modify: `commands` (использовать help-functions)

- [ ] **Step 1: Создать `help-functions`**

```bash
#!/usr/bin/env bash
# help-functions: human-readable help texts per subcommand.

cmd_create_help() {
  cat <<EOF
generic:create <service> <image[:tag]> [flags]

Create a new generic service from a Docker image.

Flags:
  --port N                Port inside container (for link/expose)
  --scheme STR            URL scheme for <PREFIX>_URL (default: tcp)
  --env KEY=VAL           Container env var (repeatable)
  --link-env KEY=VAL      Extra env injected into linked apps (repeatable)
  --mount SPEC            Mount: /container/path | /host:/container | name:/container[:ro|:rw]
  --expose H:C            Expose port to host immediately (repeatable; needs Plan 5)
  --cmd "..."             CMD-override (placed after image)
  --entrypoint /bin/x     Entrypoint-override
  --docker-arg ARG        Extra arg to docker run (repeatable)
  --no-start              Create state, don't start container
EOF
}

cmd_destroy_help() { cat <<EOF
generic:destroy <service> [-f|--force]

Delete a service: container, network, named volumes, state.
Blocked if service has active links. Without --force prompts for service name.
EOF
}

cmd_list_help() { cat <<EOF
generic:list

List all generic services with image and status.
EOF
}

cmd_exists_help() { cat <<EOF
generic:exists <service>

Exit 0 if service exists, 1 otherwise.
EOF
}

cmd_info_help() { cat <<EOF
generic:info <service> [--image|--status|--port|--internal-ip|--links|--exposed-ports]

Show service information. Without flag prints all fields.
EOF
}

cmd_config_help() { cat <<EOF
generic:config <service>

Print service configuration: env vars, link-env vars, mounts, exposed ports, port, scheme.
EOF
}
```

- [ ] **Step 2: Modify `commands` to use help-functions**

Заменить `case "$1" in generic:help|generic) ... ;; ` на вызов help-functions:

```bash
case "$1" in
  generic:help|generic)
    PLUGIN_BASE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$PLUGIN_BASE_PATH/help-functions"
    cat <<EOF
Usage: dokku generic[:COMMAND] ...

Commands:
$(cmd_create_help | head -3)
$(cmd_destroy_help | head -3)
$(cmd_list_help | head -3)
$(cmd_exists_help | head -3)
$(cmd_info_help | head -3)
$(cmd_config_help | head -3)

For full help on a command: dokku generic:<command> --help (TBD in Plan 8)
EOF
    ;;
```

- [ ] **Step 3: Make executable, smoke**

```bash
chmod +x help-functions
./commands generic:help | head -20
```

- [ ] **Step 4: Commit**

```bash
git add help-functions commands
git commit -m "feat: help text via help-functions"
```

---

## Task 23: Shellcheck pass on all scripts

**Goal:** Все bash-скрипты проходят `shellcheck -x` без ошибок.

**Files:**
- Create: `tests/shellcheck-exclude` (если нужно — после прогона)

- [ ] **Step 1: Запустить shellcheck**

```bash
shellcheck -x commands install update config common-functions functions help-functions $(ls subcommands/*) 2>&1 | tee /tmp/shellcheck.out
```

- [ ] **Step 2: Анализ результатов**

Если есть error-уровень warnings — починить inline. Самые частые:
- SC2086 (`$var` без кавычек) — добавить `"$var"`, либо если намеренно — `# shellcheck disable=SC2086` рядом.
- SC2046 (command substitution без кавычек, расщепление слов) — то же.

- [ ] **Step 3: Создать `tests/shellcheck-exclude` если нужно**

```
SC2034
SC2155
```
(только то, что подавлено глобально; точечные подавления — через `# shellcheck disable=` в коде).

- [ ] **Step 4: Re-run**

```bash
shellcheck -x --exclude="$(tr '\n' ',' < tests/shellcheck-exclude)" commands install config common-functions functions help-functions $(ls subcommands/*)
```
Expected: exit 0, no output.

- [ ] **Step 5: Commit**

```bash
git add tests/shellcheck-exclude commands install config common-functions functions help-functions subcommands/
git commit -m "chore: shellcheck pass on all scripts"
```

---

## Task 24: Full integration smoke (manual)

**Goal:** Cross-feature smoke test для уверенности что всё работает вместе.

- [ ] **Step 1: Развернуть Dokku**

```bash
./tests/setup-dokku.sh
```

- [ ] **Step 2: Создать сервис со всеми флагами**

```bash
docker exec dokku-generic-test dokku generic:create demo redis:7-alpine \
  --port 6379 \
  --scheme redis \
  --env REDIS_PASSWORD=secret \
  --link-env DEMO_URL=redis://:secret@dokku-generic-demo:6379 \
  --mount /data \
  --cmd "redis-server --requirepass secret"
```

- [ ] **Step 3: Проверить состояние**

```bash
docker exec dokku-generic-test dokku generic:list
docker exec dokku-generic-test dokku generic:info demo
docker exec dokku-generic-test dokku generic:config demo
docker exec dokku-generic-test dokku generic:exists demo; echo "exit=$?"
docker exec dokku-generic-test dokku generic:exists missing; echo "exit=$?"
```
Expected: list показывает demo, info показывает running, config показывает все env/link-env/mounts.

- [ ] **Step 4: Проверить контейнер реально работает**

```bash
docker exec dokku-generic-test docker exec dokku-generic-demo redis-cli -a secret ping
```
Expected: `PONG`.

- [ ] **Step 5: Удалить**

```bash
docker exec dokku-generic-test dokku generic:destroy demo --force
docker exec dokku-generic-test dokku generic:exists demo; echo "exit=$?"
```
Expected: exit 1 (не существует).

- [ ] **Step 6: Teardown**

```bash
./tests/teardown-dokku.sh
```

- [ ] **Step 7: Финальный коммит (если в smoke что-то правил)**

```bash
git status
# если есть правки — закоммить с описанием
```

---

## Self-Review Checklist (для исполнителя)

После прохождения всех задач:

1. **Spec coverage:** свериться с разделом 3.1 спеки (lifecycle subcommands), 3.2 (info/config), 4 (модель данных). Все ли нужные state-файлы создаются (`IMAGE`, `PORT`, `SCHEME`, `ENV`, `LINK_ENV`, `MOUNTS`, `EXPOSED_PORTS`, `CMD`, `ENTRYPOINT`, `DOCKER_ARGS`, `CREATED_AT`, `ID`)? `LINKS` сейчас пустой/отсутствует — это ок, его наполнит Plan 4.
2. **No placeholder steps remain.**
3. **`make unit-tests`** проходит локально.
4. **`make integration-tests`** проходит на Dokku.
5. **`make lint`** проходит без warnings выше info.

После self-review запустить процесс перехода к Plan 2 (set/unset/upgrade) — это будет следующий план в серии.

---

## Conventions used in this plan

- **Все bash-скрипты** — с шапкой `#!/usr/bin/env bash` + `set -eo pipefail` + `[[ $DOKKU_TRACE ]] && set -x`.
- **PLUGIN_BASE_PATH** в subcommands — `cd $(dirname $(cd $(dirname BASH_SOURCE) && pwd)) && pwd` (subcommand лежит в `subcommands/`, нужно подняться на уровень).
- **Парсинг флагов** в bash — стандартный while+case, поддержка обеих форм `--flag value` и `--flag=value`.
- **Имена volumes** — `dokku.generic.<service>` (default) и `dokku.generic.<service>.<sha1[:12]>` (per-mount). Пользовательские named volumes — оставляем имя, как указал пользователь.
- **Atomic write state** — write to `mktemp` → `mv`. Используется в `env_set`/`env_unset`.
- **Error cleanup в `create`** — `trap cleanup_on_fail ERR` снимается через `trap - ERR` после успешного завершения.
