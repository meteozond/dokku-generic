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

@test "(generic:linked) shows none initially" {
  run dokku "$PLUGIN_COMMAND_PREFIX:linked" testpg
  assert_contains "$output" "no apps linked"
}

@test "(generic:linked) shows linked app" {
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  run dokku "$PLUGIN_COMMAND_PREFIX:linked" testpg
  assert_output "testapp"
}
