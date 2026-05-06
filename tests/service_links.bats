#!/usr/bin/env bats

load test_helper

setup() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379
  dokku apps:create testapp
}

teardown() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(generic:links) lists services linked to app" {
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  run dokku "$PLUGIN_COMMAND_PREFIX:links" testapp
  assert_output "testpg"
}
