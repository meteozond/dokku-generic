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
