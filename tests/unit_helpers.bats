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
