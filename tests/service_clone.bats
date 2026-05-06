#!/usr/bin/env bats

load test_helper

setup() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/src/LINKS" 2>/dev/null || true
  rm -f "$PLUGIN_DATA_HOST_ROOT/newsvc/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" src 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" newsvc 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" src redis:7-alpine \
    --port 6379 --scheme redis \
    --env FOO=bar \
    --link-env LINKED_URL=redis://x \
    --mount /data
}

teardown() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/src/LINKS" 2>/dev/null || true
  rm -f "$PLUGIN_DATA_HOST_ROOT/newsvc/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" src 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" newsvc 2>/dev/null || true
}

@test "(generic:clone) copies state to new service" {
  run dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc
  assert_success

  run cat "$PLUGIN_DATA_HOST_ROOT/newsvc/IMAGE"
  assert_output "redis:7-alpine"
  run cat "$PLUGIN_DATA_HOST_ROOT/newsvc/PORT"
  assert_output "6379"
  run cat "$PLUGIN_DATA_HOST_ROOT/newsvc/ENV"
  assert_contains "$output" "FOO=bar"
  run cat "$PLUGIN_DATA_HOST_ROOT/newsvc/LINK_ENV"
  assert_contains "$output" "LINKED_URL=redis://x"
}

@test "(generic:clone) creates separate network and starts new container" {
  dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc

  run docker network inspect dokku-generic-newsvc
  assert_success
  run docker container inspect -f '{{.State.Status}}' dokku-generic-newsvc
  assert_output "running"
}

@test "(generic:clone) clears LINKS in new service" {
  echo "someapp" > "$PLUGIN_DATA_HOST_ROOT/src/LINKS"
  dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc
  [[ ! -s "$PLUGIN_DATA_HOST_ROOT/newsvc/LINKS" ]]
}

@test "(generic:clone) volumes are empty by default" {
  # Write data into src's volume
  dokku "$PLUGIN_COMMAND_PREFIX:exec" src sh -c "echo 'srcdata' > /data/marker.txt"
  dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc

  run dokku "$PLUGIN_COMMAND_PREFIX:exec" newsvc sh -c "test -f /data/marker.txt && echo found || echo missing"
  assert_output "missing"
}

@test "(generic:clone --copy-volumes) copies data" {
  dokku "$PLUGIN_COMMAND_PREFIX:exec" src sh -c "echo 'srcdata' > /data/marker.txt"
  dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc --copy-volumes

  run dokku "$PLUGIN_COMMAND_PREFIX:exec" newsvc cat /data/marker.txt
  assert_output "srcdata"
}

@test "(generic:clone) override flags work" {
  dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc --env FOO=newbar --port 6380
  run cat "$PLUGIN_DATA_HOST_ROOT/newsvc/ENV"
  assert_contains "$output" "FOO=newbar"
  run cat "$PLUGIN_DATA_HOST_ROOT/newsvc/PORT"
  assert_output "6380"
}

@test "(generic:clone) error when target exists" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" newsvc redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc
  assert_failure
}
