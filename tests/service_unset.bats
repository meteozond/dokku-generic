#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testunset 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testunset redis:7-alpine \
    --env FOO=bar --env BAZ=qux \
    --link-env DATABASE_URL=postgres://x \
    --mount /data --mount /etc/conf \
    --docker-arg --user=1000
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testunset 2>/dev/null || true
}

@test "(generic:unset --env) removes env key" {
  dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --env FOO
  run cat "$PLUGIN_DATA_HOST_ROOT/testunset/ENV"
  assert_not_contains "$output" "FOO"
  assert_contains "$output" "BAZ=qux"
}

@test "(generic:unset --link-env) removes link-env key" {
  dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --link-env DATABASE_URL
  run cat "$PLUGIN_DATA_HOST_ROOT/testunset/LINK_ENV" 2>/dev/null
  assert_not_contains "$output" "DATABASE_URL"
}

@test "(generic:unset --mount) removes mount entry" {
  dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --mount /data
  run cat "$PLUGIN_DATA_HOST_ROOT/testunset/MOUNTS"
  assert_not_contains "$output" "/data"
  assert_contains "$output" "/etc/conf"
}

@test "(generic:unset --docker-arg) removes specific docker arg" {
  dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --docker-arg --user=1000
  run cat "$PLUGIN_DATA_HOST_ROOT/testunset/DOCKER_ARGS" 2>/dev/null
  assert_not_contains "$output" "--user=1000"
}

@test "(generic:unset) restarts service" {
  initial_id=$(docker container inspect -f '{{.Id}}' dokku.generic.testunset)
  dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --env FOO
  new_id=$(docker container inspect -f '{{.Id}}' dokku.generic.testunset)
  [[ "$initial_id" != "$new_id" ]]
}

@test "(generic:unset) accepts multiple at once" {
  dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --env FOO --env BAZ --mount /data
  run cat "$PLUGIN_DATA_HOST_ROOT/testunset/ENV"
  assert_not_contains "$output" "FOO"
  assert_not_contains "$output" "BAZ"
}

@test "(generic:unset) is no-op for missing key" {
  run dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --env DOESNOTEXIST
  assert_success
}
