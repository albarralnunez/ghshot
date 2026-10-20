#!/usr/bin/env bats
#
# Hermetic tests for bridge/ghshot-bridge's one-shot flags. No server is
# started and no network is used; HOME is a temp dir so the real token file
# is never read.

setup() {
  BRIDGE="${BATS_TEST_DIRNAME}/../bridge/ghshot-bridge"
  TMP="$(mktemp -d)"
  export HOME="$TMP"
  unset GHSHOT_BRIDGE_HOST GHSHOT_BRIDGE_PORT
  export GHSHOT_BRIDGE_TOKEN=bats-test-token
}

teardown() { rm -rf "$TMP"; }

@test "--print-bridge-entry prints the import shape from --host/--port" {
  run python3 "$BRIDGE" --print-bridge-entry --host 100.69.42.73 --port 41330
  [ "$status" -eq 0 ]
  [ "$output" = '{"bridges": [{"url": "http://100.69.42.73:41330", "token": "bats-test-token"}]}' ]
}

@test "--print-bridge-entry reads the token file when no env token is set" {
  unset GHSHOT_BRIDGE_TOKEN
  printf 'from-the-file\n' >"$TMP/tok"
  chmod 600 "$TMP/tok"
  run python3 "$BRIDGE" --print-bridge-entry --host 10.0.0.5 --token-file "$TMP/tok"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"url": "http://10.0.0.5:41330"'* ]]
  [[ "$output" == *'"token": "from-the-file"'* ]]
}

@test "--print-bridge-entry brackets an IPv6 host" {
  run python3 "$BRIDGE" --print-bridge-entry --host fd7a:115c:a1e0::1 --port 41331
  [ "$status" -eq 0 ]
  [[ "$output" == *'"url": "http://[fd7a:115c:a1e0::1]:41331"'* ]]
}

@test "--print-bridge-entry refuses a loopback host, without printing the token" {
  for host in 127.0.0.1 localhost ::1; do
    run python3 "$BRIDGE" --print-bridge-entry --host "$host"
    [ "$status" -ne 0 ]
    [[ "$output" == *"loopback"* ]]
    [[ "$output" != *"bats-test-token"* ]]
  done
}

@test "--print-bridge-entry refuses the default (loopback) host" {
  run python3 "$BRIDGE" --print-bridge-entry
  [ "$status" -ne 0 ]
  [[ "$output" == *"loopback"* ]]
}

@test "--print-bridge-entry refuses a wildcard host" {
  run python3 "$BRIDGE" --print-bridge-entry --host 0.0.0.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"wildcard"* ]]
}

@test "--url overrides a loopback host" {
  run python3 "$BRIDGE" --print-bridge-entry --url http://dan-main.tail.example:41330/
  [ "$status" -eq 0 ]
  [[ "$output" == *'"url": "http://dan-main.tail.example:41330"'* ]]
}

@test "--url must be scheme://host[:port]" {
  for bad in ftp://x:1 http:// "http://x:1/v1/poll" "http://user@x:1" "http://:pw@x:1" "http://x:1?" "http://x#"; do
    run python3 "$BRIDGE" --print-bridge-entry --url "$bad"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--url must be"* ]]
  done
}

@test "--url rejects an invalid port" {
  for bad in "http://x:abc" "http://x:99999"; do
    run python3 "$BRIDGE" --print-bridge-entry --url "$bad"
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid port"* ]]
  done
}

@test "--print-bridge-entry refuses loopback and wildcard shorthands" {
  for host in 0 127.1 localhost.; do
    run python3 "$BRIDGE" --print-bridge-entry --host "$host"
    [ "$status" -ne 0 ]
    [[ "$output" == *"loopback"* || "$output" == *"wildcard"* ]]
  done
}

@test "--print-token and --print-bridge-entry are mutually exclusive" {
  run python3 "$BRIDGE" --print-token --print-bridge-entry --host 10.0.0.5
  [ "$status" -ne 0 ]
  [[ "$output" != *"bats-test-token"* ]]
}

@test "--url without --print-bridge-entry is an error" {
  run python3 "$BRIDGE" --url http://x:1
  [ "$status" -ne 0 ]
  [[ "$output" == *"only applies to --print-bridge-entry"* ]]
}

@test "--print-bridge-entry does not create a token file when refusing" {
  unset GHSHOT_BRIDGE_TOKEN
  run python3 "$BRIDGE" --print-bridge-entry --token-file "$TMP/new-token"
  [ "$status" -ne 0 ]
  [ ! -e "$TMP/new-token" ]
}
