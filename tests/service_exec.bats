#!/usr/bin/env bats
load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testexec 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testexec redis:7-alpine
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testexec 2>/dev/null || true
}

@test "(generic:exec) runs command and captures output" {
  run dokku "$PLUGIN_COMMAND_PREFIX:exec" testexec redis-cli ping
  assert_success
  assert_output "PONG"
}

@test "(generic:exec) propagates non-zero exit" {
  run dokku "$PLUGIN_COMMAND_PREFIX:exec" testexec false
  [[ "$status" -ne 0 ]]
}

@test "(generic:exec) error when not running" {
  docker container stop dokku.generic.testexec
  run dokku "$PLUGIN_COMMAND_PREFIX:exec" testexec echo hi
  assert_failure
}
