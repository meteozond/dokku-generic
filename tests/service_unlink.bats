#!/usr/bin/env bats

load test_helper

setup() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379 --scheme redis
  dokku apps:create testapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
}

teardown() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(generic:unlink) removes config and docker-options" {
  run dokku "$PLUGIN_COMMAND_PREFIX:unlink" testpg testapp
  assert_success

  run cat "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS"
  assert_not_contains "$output" "testapp"

  run dokku docker-options:report testapp
  assert_not_contains "$output" "--network=dokku.generic.testpg"

  run dokku config:get testapp TESTPG_URL
  assert_output ""
}

@test "(generic:unlink) error when not linked" {
  dokku "$PLUGIN_COMMAND_PREFIX:unlink" testpg testapp
  run dokku "$PLUGIN_COMMAND_PREFIX:unlink" testpg testapp
  assert_failure
}
