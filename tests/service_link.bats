#!/usr/bin/env bats

load test_helper

setup() {
  # Clear LINKS so destroy doesn't block on linked-service check
  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379 --scheme redis --link-env LINKED=yes
  dokku apps:create testapp
}

teardown() {
  # Clear LINKS before destroy so the destroy check doesn't block
  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS" 2>/dev/null || true
  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg2/LINKS" 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg2 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(generic:link) creates network connection and config" {
  run dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  assert_success

  # LINKS file updated
  run cat "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS"
  assert_contains "$output" "testapp"

  # network is attached via attach-post-create, not docker-options
  run dokku network:report testapp --network-attach-post-create
  assert_contains "$output" "dokku.generic.testpg"
  run dokku docker-options:report testapp
  assert_not_contains "$output" "--network=dokku.generic.testpg"

  # config has TESTPG_URL/HOST/PORT
  run dokku config:get testapp TESTPG_URL
  assert_output "redis://dokku.generic.testpg:6379"
  run dokku config:get testapp TESTPG_HOST
  assert_output "dokku.generic.testpg"
  run dokku config:get testapp TESTPG_PORT
  assert_output "6379"

  # custom link-env propagated
  run dokku config:get testapp LINKED
  assert_output "yes"
}

@test "(generic:link --alias) uses custom prefix" {
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp --alias DATABASE
  run dokku config:get testapp DATABASE_URL
  assert_output "redis://dokku.generic.testpg:6379"
  run dokku config:get testapp TESTPG_URL
  assert_output ""
}

@test "(generic:link) error when already linked" {
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  run dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  assert_failure
  assert_contains "$output" "Already linked"
}

@test "(generic:link) generates alternative prefix when default occupied" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg2 redis:7-alpine --port 6379 --scheme redis
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg2 testapp --alias TESTPG
  run dokku config:get testapp TESTPG2_URL
  assert_contains "$output" "dokku.generic.testpg2"
}

@test "(generic:link) error when app missing" {
  run dokku "$PLUGIN_COMMAND_PREFIX:link" testpg nonexistent
  assert_failure
}

@test "(generic:link) interpolates %h %p %s in link-env values" {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg2 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg2 redis:7-alpine --port 6379 --scheme redis \
    --link-env DATABASE_URL='redis://%s-user:secret@%h:%p/0' \
    --link-env CUSTOM_HOST_ONLY='%h'
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg2 testapp

  run dokku config:get testapp DATABASE_URL
  assert_output "redis://redis-user:secret@dokku.generic.testpg2:6379/0"

  run dokku config:get testapp CUSTOM_HOST_ONLY
  assert_output "dokku.generic.testpg2"

  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg2/LINKS"
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg2
}

@test "(generic:link) %% escapes literal % in link-env values" {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg2 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg2 redis:7-alpine --port 6379 --scheme redis \
    --link-env LITERAL='%%h is %h' \
    --link-env DOUBLE_PERCENT='100%% sure: %h:%p'
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg2 testapp

  run dokku config:get testapp LITERAL
  assert_output "%h is dokku.generic.testpg2"

  run dokku config:get testapp DOUBLE_PERCENT
  assert_output "100% sure: dokku.generic.testpg2:6379"

  rm -f "$PLUGIN_DATA_HOST_ROOT/testpg2/LINKS"
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg2
}

@test "(generic:link) regression: app keeps its default network, so the proxy gets an upstream" {
  run dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  assert_success
  # A --network docker option in any phase replaces the default bridge and
  # Dokku then writes "location / { return 502; }".
  for phase in build deploy run; do
    run dokku docker-options:report testapp "--docker-options-$phase"
    assert_not_contains "$output" "--network"
  done
  run dokku network:report testapp --network-attach-post-create
  assert_contains "$output" "dokku.generic.testpg"
  run dokku network:report testapp --network-initial-network
  assert_not_contains "$output" "dokku.generic.testpg"
}

@test "(generic:link) drops legacy --network docker-options left by older versions" {
  dokku docker-options:add testapp build,deploy,run "--network=dokku.generic.testpg"
  run dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  run dokku docker-options:report testapp
  assert_not_contains "$output" "--network=dokku.generic.testpg"
  run dokku network:report testapp --network-attach-post-create
  assert_contains "$output" "dokku.generic.testpg"
}

@test "(generic:link) keeps other networks in attach-post-create" {
  dokku network:create othernet
  dokku network:set testapp attach-post-create othernet
  run dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  run dokku network:report testapp --network-attach-post-create
  assert_contains "$output" "othernet"
  assert_contains "$output" "dokku.generic.testpg"
  dokku "$PLUGIN_COMMAND_PREFIX:unlink" testpg testapp
  run dokku network:report testapp --network-attach-post-create
  assert_contains "$output" "othernet"
  assert_not_contains "$output" "dokku.generic.testpg"
  dokku network:set testapp attach-post-create
  dokku network:destroy othernet --force
}

@test "(generic:link) on a linked app migrates legacy options, then fails" {
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  dokku network:set testapp attach-post-create
  dokku docker-options:add testapp deploy "--network=dokku.generic.testpg"
  run dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  assert_failure
  assert_contains "$output" "Already linked"
  run dokku docker-options:report testapp
  assert_not_contains "$output" "--network=dokku.generic.testpg"
  run dokku network:report testapp --network-attach-post-create
  assert_contains "$output" "dokku.generic.testpg"
}
