#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testset 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testset redis:7-alpine
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testset 2>/dev/null || true
}

@test "(generic:set --image) updates image and restarts" {
  run dokku "$PLUGIN_COMMAND_PREFIX:set" testset --image redis:7
  assert_success
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/IMAGE"
  assert_output "redis:7"
  run docker container inspect -f '{{.Config.Image}}' "dokku.generic.testset"
  assert_output "redis:7"
}

@test "(generic:set --port) updates port" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --port 6380
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/PORT"
  assert_output "6380"
}

@test "(generic:set --scheme) updates scheme" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --scheme redis
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/SCHEME"
  assert_output "redis"
}

@test "(generic:set --env) adds and updates env vars" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --env FOO=bar
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/ENV"
  assert_contains "$output" "FOO=bar"
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --env FOO=baz
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/ENV"
  assert_contains "$output" "FOO=baz"
  assert_not_contains "$output" "FOO=bar"
}

@test "(generic:set --link-env) updates link-env" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --link-env DATABASE_URL=postgres://x
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/LINK_ENV"
  assert_contains "$output" "DATABASE_URL=postgres://x"
}

@test "(generic:set --mount) appends mount" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --mount /data
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --mount /etc/conf
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/MOUNTS"
  assert_contains "$output" "/data"
  assert_contains "$output" "/etc/conf"
}

@test "(generic:set --cmd) updates CMD" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --cmd "redis-server --bind 0.0.0.0"
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/CMD"
  assert_output "redis-server --bind 0.0.0.0"
}

@test "(generic:set --entrypoint) updates ENTRYPOINT" {
  # Stop container so set doesn't try to restart with bad entrypoint
  docker container stop dokku.generic.testset 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --entrypoint /bin/myinit
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/ENTRYPOINT"
  assert_output "/bin/myinit"
}

@test "(generic:set --docker-arg) appends docker arg" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --docker-arg --user=1000
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/DOCKER_ARGS"
  assert_contains "$output" "--user=1000"
}

@test "(generic:set) restarts container after change" {
  initial_id=$(docker container inspect -f '{{.Id}}' dokku.generic.testset)
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --env NEW=var
  new_id=$(docker container inspect -f '{{.Id}}' dokku.generic.testset)
  [[ "$initial_id" != "$new_id" ]] || flunk "expected container to be recreated"
}

@test "(generic:set) error when service missing" {
  run dokku "$PLUGIN_COMMAND_PREFIX:set" missing --image redis:7
  assert_failure
}

@test "(generic:set) accepts multiple flags in one call" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --image redis:7 --env FOO=bar --port 6379
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/IMAGE"
  assert_output "redis:7"
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/PORT"
  assert_output "6379"
}

@test "(generic:set --env) rejects malformed pair without =" {
  run dokku "$PLUGIN_COMMAND_PREFIX:set" testset --env NOEQUALS
  assert_failure
  assert_contains "$output" "Invalid --env"
}

@test "(generic:set --env) rejects lowercase key" {
  run dokku "$PLUGIN_COMMAND_PREFIX:set" testset --env docker_host=foo
  assert_failure
  assert_contains "$output" "Invalid --env key"
}

@test "(generic:set --mount) deduplicates repeated spec" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --mount /data
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --mount /data
  count=$(grep -cxF "/data" "$PLUGIN_DATA_HOST_ROOT/testset/MOUNTS")
  [[ "$count" -eq 1 ]] || flunk "expected one /data entry, got $count"
}

@test "(generic:set --no-restart) skips restart on running service" {
  # Grab container start time before set
  before=$(docker container inspect -f '{{.State.StartedAt}}' dokku.generic.testset)
  sleep 1
  run dokku "$PLUGIN_COMMAND_PREFIX:set" testset --env FOO=bar --no-restart
  assert_success
  after=$(docker container inspect -f '{{.State.StartedAt}}' dokku.generic.testset)
  [[ "$before" == "$after" ]] || flunk "container was restarted despite --no-restart (before=$before after=$after)"
}

@test "(generic:set) concurrent invocations serialize via lock" {
  # Two concurrent sets — the second must wait for the first. If they raced
  # they'd interleave restarts; with the lock, wall-clock is roughly 2x the
  # single-call time and both succeed.
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --env=FIRST=1 &
  first_pid=$!
  sleep 0.2
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --env=SECOND=2 &
  second_pid=$!
  wait $first_pid
  first_ec=$?
  wait $second_pid
  second_ec=$?
  [[ $first_ec -eq 0 ]] || flunk "first set failed"
  [[ $second_ec -eq 0 ]] || flunk "second set failed"
  # Both env values should be present — neither trampled the other.
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/ENV"
  assert_contains "$output" "FIRST=1"
  assert_contains "$output" "SECOND=2"
}
