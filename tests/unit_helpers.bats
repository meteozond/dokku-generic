#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

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

@test "verify_service_name accepts single letter" {
  run verify_service_name "Z"
  assert_success
}

@test "verify_service_name rejects leading underscore" {
  run verify_service_name "_underscore"
  assert_failure
}

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

@test "parse_mount_spec accepts uppercase :RO suffix" {
  run parse_mount_spec "/host:/container:RO"
  assert_success
  assert_output "bind|/host|/container|ro"
}

@test "parse_mount_spec accepts uppercase :RW suffix" {
  run parse_mount_spec "myvol:/container:RW"
  assert_success
  assert_output "named|myvol|/container|rw"
}

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

@test "service_container_name returns dokku.generic.<svc>" {
  run service_container_name "myservice"
  assert_output "dokku.generic.myservice"
}

@test "service_network_name returns dokku.generic.<svc>" {
  run service_network_name "myservice"
  assert_output "dokku.generic.myservice"
}

@test "build_run_args includes -e flags from ENV" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  echo "redis:7" > "$tmp/myservice/IMAGE"
  env_set "$tmp/myservice/ENV" "FOO" "bar"
  build_run_args "myservice"
  local joined="${_DOCKER_RUN_ARGS[*]}"
  assert_contains "$joined" "-e FOO=bar"
  rm -rf "$tmp"
}

@test "build_run_args includes -v for default volume when MOUNTS empty" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  echo "redis:7" > "$tmp/myservice/IMAGE"
  build_run_args "myservice"
  local joined="${_DOCKER_RUN_ARGS[*]}"
  # No mounts file → no -v expected; volume is created on demand at first --mount
  [[ ! "$joined" =~ "-v " ]] || flunk "expected no -v but got: $joined"
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
  build_run_args "myservice"
  local joined="${_DOCKER_RUN_ARGS[*]}"
  # plain path → named auto volume
  assert_contains "$joined" "-v dokku.generic.myservice."
  assert_contains "$joined" ":/var/lib/data"
  # bind mount with ro
  assert_contains "$joined" "-v /host/path:/container/path:ro"
  # named with explicit name
  assert_contains "$joined" "-v myvol:/var/log"
  rm -rf "$tmp"
}

@test "build_run_args includes --entrypoint when ENTRYPOINT file present" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  echo "redis:7" > "$tmp/myservice/IMAGE"
  echo "/bin/myinit" > "$tmp/myservice/ENTRYPOINT"
  build_run_args "myservice"
  local joined="${_DOCKER_RUN_ARGS[*]}"
  assert_contains "$joined" "--entrypoint /bin/myinit"
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
  build_run_args "myservice"
  local joined="${_DOCKER_RUN_ARGS[*]}"
  assert_contains "$joined" "--user=1000:1000"
  assert_contains "$joined" "--cap-add=NET_ADMIN"
  rm -rf "$tmp"
}

@test "build_cmd_args returns CMD content" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  echo "server /data --bind 0.0.0.0" > "$tmp/myservice/CMD"
  build_cmd_args "myservice"
  local joined="${_DOCKER_CMD_ARGS[*]}"
  assert_equal "$joined" "server /data --bind 0.0.0.0"
  rm -rf "$tmp"
}

@test "build_cmd_args returns empty when no CMD file" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  build_cmd_args "myservice"
  [[ ${#_DOCKER_CMD_ARGS[@]} -eq 0 ]] || flunk "expected empty array, got: ${_DOCKER_CMD_ARGS[*]}"
  rm -rf "$tmp"
}

@test "build_run_args preserves whitespace in --docker-arg values" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/myservice"
  echo "redis:7" > "$tmp/myservice/IMAGE"
  printf '%s\n' '--label=team=hello world' '--cap-add=NET_ADMIN' > "$tmp/myservice/DOCKER_ARGS"
  build_run_args "myservice"
  # The first DOCKER_ARG should be exactly one element with the space preserved
  [[ "${_DOCKER_RUN_ARGS[0]}" == "--label=team=hello world" ]] || flunk "expected single arg with space, got: ${_DOCKER_RUN_ARGS[0]}"
  [[ "${_DOCKER_RUN_ARGS[1]}" == "--cap-add=NET_ADMIN" ]] || flunk "expected second arg, got: ${_DOCKER_RUN_ARGS[1]}"
  rm -rf "$tmp"
}

@test "service_is_running returns 1 when container missing" {
  PLUGIN_DATA_ROOT="$(mktemp -d)"
  mkdir -p "$PLUGIN_DATA_ROOT/missing"
  run service_is_running "missing"
  assert_failure
  rm -rf "$PLUGIN_DATA_ROOT"
}

@test "service_alias returns uppercase service name with - and . to _" {
  run service_alias "my-svc"
  assert_output "MY_SVC"
}

@test "service_alias handles dots" {
  run service_alias "my.svc"
  assert_output "MY_SVC"
}

@test "service_alias plain name uppercased" {
  run service_alias "pg"
  assert_output "PG"
}

@test "service_url returns scheme://container:port" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/pg"
  echo "5432" > "$tmp/pg/PORT"
  echo "postgres" > "$tmp/pg/SCHEME"
  run service_url "pg"
  assert_output "postgres://dokku.generic.pg:5432"
  rm -rf "$tmp"
}

@test "service_url returns empty when no port" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/pg"
  echo "tcp" > "$tmp/pg/SCHEME"
  run service_url "pg"
  assert_output ""
  rm -rf "$tmp"
}

@test "service_ambassador_name returns <container>.ambassador" {
  run service_ambassador_name "myservice"
  assert_output "dokku.generic.myservice.ambassador"
}

@test "list_service_volumes returns nothing when no volumes for service" {
  # This test is fine on host since it just runs docker volume ls + grep;
  # if no volumes match the pattern, output is empty
  run list_service_volumes "nonexistent-svc-name-xyz123"
  assert_success
  assert_output ""
}
