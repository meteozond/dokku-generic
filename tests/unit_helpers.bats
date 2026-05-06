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
