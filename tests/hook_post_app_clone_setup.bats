#!/usr/bin/env bats

load test_helper

setup() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force srcapp 2>/dev/null || true
  dokku apps:destroy --force dstapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379
  dokku apps:create srcapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg srcapp
}

teardown() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force srcapp 2>/dev/null || true
  dokku apps:destroy --force dstapp 2>/dev/null || true
}

@test "(hook post-app-clone-setup) propagates link to clone" {
  dokku apps:clone srcapp dstapp
  run cat "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS"
  assert_contains "$output" "dstapp"
  run dokku config:get dstapp TESTPG_HOST
  assert_output "dokku.generic.testpg"
}
