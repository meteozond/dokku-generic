#!/usr/bin/env bats
load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testenter 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testenter redis:7-alpine
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testenter 2>/dev/null || true
}

@test "(generic:enter) drops into shell (sh fallback for alpine)" {
  run bash -c "echo 'echo hello-from-shell; exit' | dokku '$PLUGIN_COMMAND_PREFIX:enter' testenter"
  assert_success
  assert_contains "$output" "hello-from-shell"
}

@test "(generic:enter) error when not running" {
  docker container stop dokku-generic-testenter
  run dokku "$PLUGIN_COMMAND_PREFIX:enter" testenter
  assert_failure
}
