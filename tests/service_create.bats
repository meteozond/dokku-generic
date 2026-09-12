#!/usr/bin/env bats

load test_helper

teardown() {
  # Try the destroy subcommand first (becomes available in Task 19).
  # Fall back to direct state + container cleanup so tests can run before destroy lands.
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testcreate 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" service-with-dashes 2>/dev/null || true
  # Direct fallback cleanup
  local _svc
  for _svc in testcreate service-with-dashes; do
    docker container rm -f "dokku.generic.${_svc}" >/dev/null 2>&1 || true
    docker network rm "dokku.generic.${_svc}" >/dev/null 2>&1 || true
    rm -rf "/var/lib/dokku/services/generic/${_svc}"
  done
}

@test "(generic:create) success with image" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  assert_success
  assert_contains "$output" "container created: testcreate"
}

@test "(generic:create) records image in state" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/IMAGE"
  assert_output "redis:7-alpine"
}

@test "(generic:create) creates docker network" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  run docker network inspect "dokku.generic.testcreate"
  assert_success
}

@test "(generic:create) starts running container" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  run docker container inspect -f '{{.State.Status}}' "dokku.generic.testcreate"
  assert_output "running"
}

@test "(generic:create) accepts service name with dashes" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create" service-with-dashes redis:7-alpine
  assert_success
  assert_contains "$output" "container created: service-with-dashes"
}

@test "(generic:create) error when no name" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create"
  assert_failure
  assert_contains "$output" "Please specify a valid name"
}

@test "(generic:create) error when no image" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate
  assert_failure
  assert_contains "$output" "Please specify a docker image"
}

@test "(generic:create) error when name has dot" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create" "bad.name" redis:7-alpine
  assert_failure
}

@test "(generic:create) error when service already exists" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  assert_failure
  assert_contains "$output" "already exists"
}

@test "(generic:create --port) records port" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --port 6379
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/PORT"
  assert_output "6379"
}

@test "(generic:create --scheme) records scheme" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --scheme redis
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/SCHEME"
  assert_output "redis"
}

@test "(generic:create --env) writes env to ENV file" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --env FOO=bar --env BAZ=qux
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/ENV"
  assert_contains "$output" "FOO=bar"
  assert_contains "$output" "BAZ=qux"
}

@test "(generic:create --link-env) writes to LINK_ENV file" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --link-env DATABASE_URL=redis://x
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/LINK_ENV"
  assert_contains "$output" "DATABASE_URL=redis://x"
}

@test "(generic:create --mount) writes to MOUNTS file" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --mount /var/lib/data --mount /host:/container:ro
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/MOUNTS"
  assert_contains "$output" "/var/lib/data"
  assert_contains "$output" "/host:/container:ro"
}

@test "(generic:create --cmd) writes CMD" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --cmd "redis-server --bind 0.0.0.0"
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/CMD"
  assert_output "redis-server --bind 0.0.0.0"
}

@test "(generic:create --entrypoint) writes ENTRYPOINT" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --no-start --entrypoint /bin/myinit
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/ENTRYPOINT"
  assert_output "/bin/myinit"
}

@test "(generic:create --docker-arg) appends to DOCKER_ARGS" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --docker-arg --user=1000 --docker-arg --cap-add=NET_ADMIN
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/DOCKER_ARGS"
  assert_contains "$output" "--user=1000"
  assert_contains "$output" "--cap-add=NET_ADMIN"
}

@test "(generic:create --no-start) creates state but no container" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --no-start
  run docker container inspect "dokku.generic.testcreate"
  assert_failure
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/IMAGE"
  assert_output "redis:7-alpine"
}

@test "(generic:create --expose) records expose for later activation" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --no-start --expose 6379:6379
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/EXPOSED_PORTS"
  assert_contains "$output" "6379:6379"
}

@test "(generic:create --env=KEY=VALUE) supports = form" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --env=FOO=bar
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/ENV"
  assert_contains "$output" "FOO=bar"
}

@test "(generic:create) container has env from --env" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --env REDIS_PASSWORD=sekret --cmd "redis-server --requirepass sekret"
  run docker exec dokku.generic.testcreate env
  assert_contains "$output" "REDIS_PASSWORD=sekret"
}

@test "(generic:create --expose) raises ambassador for exposed port" {
  # Pick a high host port unlikely to collide
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine --expose 16379:6379
  run docker container ls -aq --filter "label=dokku.ambassador.service=testcreate" --format '{{.Names}}'
  assert_success
  [[ -n "$output" ]] || flunk "expected an ambassador container, got none"
}
