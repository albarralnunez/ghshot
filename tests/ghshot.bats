#!/usr/bin/env bats
#
# Hermetic tests for skills/ghshot/ghshot.sh.
# No network: `gh` is replaced by a stub in tests/stubs; the bridge is forced
# unhealthy so the attachments backend never auto-selects.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../skills/ghshot/ghshot.sh"
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  PATH="${STUBS}:${PATH}"
  export PATH

  # Clean any ambient ghshot config so tests are deterministic.
  unset GHSHOT_BACKEND GHSHOT_PUBLIC GHSHOT_FORCE GHSHOT_MAX_BYTES GHSHOT_REPO
  export GHSHOT_ASSUME_YES=1
  # Force the bridge unhealthy so auto-detection lands on release.
  export GHSHOT_BRIDGE_URL=http://127.0.0.1:1

  TMP="$(mktemp -d)"
  IMG="${TMP}/shot.png"
  IMG2="${TMP}/two.png"
  # Minimal valid PNG signature — content does not matter to the script.
  printf '\x89PNG\r\n\x1a\n' >"$IMG"
  printf '\x89PNG\r\n\x1a\n' >"$IMG2"
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# ---- meta / arg parsing ----------------------------------------------------

@test "--version prints version" {
  run bash "$SCRIPT" --version
  [ "$status" -eq 0 ]
  [ "$output" = "ghshot 0.1.0" ]
}

@test "--help prints usage and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"upload images to GitHub"* ]]
  [[ "$output" == *"--backend"* ]]
}

@test "no image given is an error" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no image given"* ]]
}

@test "unknown flag is rejected" {
  run bash "$SCRIPT" --definitely-not-a-flag "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

# ---- numeric validation ----------------------------------------------------

@test "--pr requires a number" {
  run bash "$SCRIPT" --pr abc "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs a number"* ]]
}

@test "--issue requires a number" {
  run bash "$SCRIPT" --issue x12 "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs a number"* ]]
}

@test "GHSHOT_MAX_BYTES must be an integer" {
  run env GHSHOT_MAX_BYTES=notanumber bash "$SCRIPT" "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be an integer"* ]]
}

# ---- vet_file guards -------------------------------------------------------

@test "refuses sensitive-looking filename" {
  s="${TMP}/.env"
  printf 'SECRET=1\n' >"$s"
  run bash "$SCRIPT" "$s"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive-looking"* ]]
}

@test "refuses non-image extension" {
  t="${TMP}/notes.txt"
  printf 'hello\n' >"$t"
  run bash "$SCRIPT" "$t"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not an image"* ]]
}

@test "refuses oversize file" {
  run env GHSHOT_MAX_BYTES=1 bash "$SCRIPT" "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"too large"* ]]
}

@test "--force bypasses the non-image guard" {
  t="${TMP}/notes.txt"
  printf 'hello\n' >"$t"
  run bash "$SCRIPT" --force "$t"
  [ "$status" -eq 0 ]
}

@test "missing file is an error" {
  run bash "$SCRIPT" "${TMP}/nope.png"
  [ "$status" -ne 0 ]
  [[ "$output" == *"file not found"* ]]
}

# ---- release backend output (default) --------------------------------------

@test "default backend is release and emits a github URL" {
  run bash "$SCRIPT" --json "$IMG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"release"'* ]]
  [[ "$output" == *'"url":"https://github.com/octocat/ghshot-images/releases/download/'* ]]
  [[ "$output" == *'"visibility":"private"'* ]]
}

@test "private release renders as a link (not inline)" {
  run bash "$SCRIPT" "$IMG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"](https://github.com/"* ]]
  [[ "$output" != *"!["* ]]
}

@test "--public release renders inline image markdown" {
  run bash "$SCRIPT" --public "$IMG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"![shot](https://github.com/"* ]]
}

@test "--raw prints a bare URL, no markdown" {
  run bash "$SCRIPT" --raw "$IMG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://github.com/octocat/ghshot-images/"* ]]
  [[ "$output" != *"!["* ]]
  [[ "$output" != *"]("* ]]
}

@test "multiple images produce one markdown line each" {
  run bash "$SCRIPT" --public "$IMG" "$IMG2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"![shot](https://github.com/"* ]]
  [[ "$output" == *"![two](https://github.com/"* ]]
}

@test "--pr posts a comment via gh stub" {
  run bash "$SCRIPT" --pr 42 "$IMG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"commented on pr #42"* ]]
}

@test "gh auth failure is reported for release backend" {
  run env GH_STUB_AUTH_FAIL=1 bash "$SCRIPT" "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"gh not authenticated"* ]]
}

# ---- backend selection / precedence ----------------------------------------

@test "explicit --backend release is honored" {
  run bash "$SCRIPT" --backend release --json "$IMG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"release"'* ]]
}

@test "GHSHOT_BACKEND env selects the backend" {
  run env GHSHOT_BACKEND=release bash "$SCRIPT" --json "$IMG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"release"'* ]]
}

@test "auto-selects release when no bridge is running" {
  # GHSHOT_BRIDGE_URL points at an unused port so bridge_healthy fails fast
  run env GHSHOT_BRIDGE_URL=http://127.0.0.1:1 bash "$SCRIPT" --json "$IMG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"backend":"release"'* ]]
}

@test "unknown backend is rejected" {
  run bash "$SCRIPT" --backend bogus "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown backend"* ]]
}
