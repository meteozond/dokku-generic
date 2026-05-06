#!/usr/bin/env bats

load test_helper

setup() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/oldsvc/LINKS" 2>/dev/null || true
  rm -f "$PLUGIN_DATA_HOST_ROOT/newsvc/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" oldsvc 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" newsvc 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" oldsvc redis:7-alpine --port 6379 --scheme redis --mount /data
  dokku apps:create testapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" oldsvc testapp
}

teardown() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/oldsvc/LINKS" 2>/dev/null || true
  rm -f "$PLUGIN_DATA_HOST_ROOT/newsvc/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" oldsvc 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" newsvc 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(generic:rename) moves state and keeps data" {
  dokku "$PLUGIN_COMMAND_PREFIX:exec" oldsvc sh -c "echo 'data' > /data/marker.txt"

  run dokku "$PLUGIN_COMMAND_PREFIX:rename" oldsvc newsvc
  assert_success

  [[ ! -d "$PLUGIN_DATA_HOST_ROOT/oldsvc" ]]
  [[ -d   "$PLUGIN_DATA_HOST_ROOT/newsvc" ]]

  run dokku "$PLUGIN_COMMAND_PREFIX:exec" newsvc cat /data/marker.txt
  assert_output "data"
}

@test "(generic:rename) updates docker-options of linked apps" {
  dokku "$PLUGIN_COMMAND_PREFIX:rename" oldsvc newsvc
  run dokku docker-options:report testapp
  assert_contains "$output" "--network=dokku-generic-newsvc"
  assert_not_contains "$output" "--network=dokku-generic-oldsvc"
}

@test "(generic:rename) updates link config vars" {
  dokku "$PLUGIN_COMMAND_PREFIX:rename" oldsvc newsvc
  run dokku config:get testapp NEWSVC_HOST
  assert_output "dokku-generic-newsvc"
  run dokku config:get testapp OLDSVC_HOST
  assert_output ""
}

@test "(generic:rename) error when target exists" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" newsvc redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:rename" oldsvc newsvc
  assert_failure
}
