#!/usr/bin/env bats

load test_helper

setup() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/svc1/LINKS" 2>/dev/null || true
  rm -f "$PLUGIN_DATA_HOST_ROOT/svc2/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" svc1 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" svc2 2>/dev/null || true
  dokku apps:destroy --force app1 2>/dev/null || true
  dokku apps:destroy --force app2 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" svc1 redis:7-alpine --port 6379
  dokku "$PLUGIN_COMMAND_PREFIX:create" svc2 redis:7-alpine --port 6379
  dokku apps:create app1
  dokku apps:create app2
  dokku "$PLUGIN_COMMAND_PREFIX:link" svc1 app1
  dokku "$PLUGIN_COMMAND_PREFIX:link" svc2 app2
}

teardown() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/svc1/LINKS" 2>/dev/null || true
  rm -f "$PLUGIN_DATA_HOST_ROOT/svc2/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" svc1 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" svc2 2>/dev/null || true
  dokku apps:destroy --force app1 2>/dev/null || true
  dokku apps:destroy --force app2 2>/dev/null || true
}

@test "isolation: app1 only has svc1's network in docker-options" {
  run dokku docker-options:report app1
  assert_contains "$output" "--network=dokku-generic-svc1"
  assert_not_contains "$output" "--network=dokku-generic-svc2"
}

@test "isolation: app2 only has svc2's network in docker-options" {
  run dokku docker-options:report app2
  assert_contains "$output" "--network=dokku-generic-svc2"
  assert_not_contains "$output" "--network=dokku-generic-svc1"
}

@test "isolation: svc1 and svc2 networks are different" {
  net1=$(docker network inspect -f '{{.Id}}' dokku-generic-svc1)
  net2=$(docker network inspect -f '{{.Id}}' dokku-generic-svc2)
  [[ "$net1" != "$net2" ]]
}
