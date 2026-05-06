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
  dokku apps:destroy --force dstapp 2>/dev/null || true
}

@test "(hook post-app-rename-setup) updates LINKS file on rename" {
  dokku apps:rename srcapp dstapp
  run cat "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS"
  assert_contains "$output" "dstapp"
  assert_not_contains "$output" "srcapp"
}
