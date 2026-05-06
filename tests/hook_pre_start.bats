#!/usr/bin/env bats

load test_helper

setup() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379
  dokku apps:create testapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
}

teardown() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(hook pre-start) starts stopped linked services when invoked directly" {
  dokku "$PLUGIN_COMMAND_PREFIX:stop" testpg
  run /var/lib/dokku/plugins/available/generic/pre-start testapp
  assert_success
  run docker container inspect -f '{{.State.Status}}' dokku-generic-testpg
  assert_output "running"
}

@test "(hook pre-start) is no-op when service running" {
  run /var/lib/dokku/plugins/available/generic/pre-start testapp
  assert_success
}
