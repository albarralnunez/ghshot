#!/usr/bin/env bats
#
# Hermetic tests for skills/ghshot/ghshot.sh (attachments-only).
# No network: `gh` and `curl` are replaced by stubs in tests/stubs. The fake
# curl makes the bridge look healthy and returns a canned user-attachments URL.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../skills/ghshot/ghshot.sh"
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  PATH="${STUBS}:${PATH}"
  export PATH

  TMP="$(mktemp -d)"
  # Isolate HOME so the real ~/.config/ghshot/bridge-token is never read.
  export HOME="$TMP"

  # Clean ambient config; provide a bridge token so uploads proceed.
  unset GHSHOT_FORCE GHSHOT_MAX_BYTES GHSHOT_REPO CURL_STUB_UNHEALTHY \
    CURL_STUB_UPLOAD_FAIL CURL_STUB_BADRESP CURL_STUB_URL GH_STUB_AUTH_FAIL
  export GHSHOT_BRIDGE_TOKEN=testtoken
  export GHSHOT_BRIDGE_URL=http://127.0.0.1:41330

  IMG="${TMP}/shot.png"
  IMG2="${TMP}/two.png"
  # Minimal valid PNG signature — content does not matter to the script/stubs.
  printf '\x89PNG\r\n\x1a\n' >"$IMG"
  cp "$IMG" "$IMG2"
}

teardown() { rm -rf "$TMP"; }

# ---- flags / validation ----------------------------------------------------

@test "--version prints version" {
  run bash "$SCRIPT" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "ghshot "* ]]
}

@test "--help prints usage and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"browser session"* ]]
  [[ "$output" == *"--pr N"* ]]
}

@test "no image given is an error" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no image given"* ]]
}

@test "unknown flag is rejected" {
  run bash "$SCRIPT" --nope "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "--pr requires a number" {
  run bash "$SCRIPT" --pr abc "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs a number"* ]]
}

@test "--issue requires a number" {
  run bash "$SCRIPT" --issue "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"needs a number"* ]]
}

@test "GHSHOT_MAX_BYTES must be an integer" {
  run env GHSHOT_MAX_BYTES=big bash "$SCRIPT" "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be an integer"* ]]
}

# ---- content guards --------------------------------------------------------

@test "refuses sensitive-looking filename" {
  cp "$IMG" "$TMP/.env"
  run bash "$SCRIPT" "$TMP/.env"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sensitive-looking"* ]]
}

@test "refuses non-image extension" {
  cp "$IMG" "$TMP/notes.txt"
  run bash "$SCRIPT" "$TMP/notes.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not an image"* ]]
}

@test "refuses oversize file" {
  run env GHSHOT_MAX_BYTES=1 bash "$SCRIPT" "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"too large"* ]]
}

@test "--force bypasses the non-image guard" {
  cp "$IMG" "$TMP/notes.txt"
  run bash "$SCRIPT" --force "$TMP/notes.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"user-attachments/assets/"* ]]
}

@test "missing file is an error" {
  run bash "$SCRIPT" "$TMP/nope.png"
  [ "$status" -ne 0 ]
  [[ "$output" == *"file not found"* ]]
}

# ---- happy path (bridge stub) ----------------------------------------------

@test "emits inline user-attachments markdown" {
  run bash "$SCRIPT" "$IMG"
  [ "$status" -eq 0 ]
  [[ "$output" == '![shot](https://github.com/user-attachments/assets/'* ]]
}

@test "--raw prints a bare URL, no markdown" {
  run bash "$SCRIPT" --raw "$IMG"
  [ "$status" -eq 0 ]
  [[ "$output" == https://github.com/user-attachments/assets/* ]]
  [[ "$output" != *'!['* ]]
}

@test "--json reports visibility private and a url" {
  run bash "$SCRIPT" --json "$IMG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"visibility":"private"'* ]]
  [[ "$output" == *'"url":"https://github.com/user-attachments/assets/'* ]]
}

@test "multiple images produce one markdown line each" {
  run bash "$SCRIPT" "$IMG" "$IMG2"
  [ "$status" -eq 0 ]
  lines_count=$(printf '%s\n' "$output" | grep -c '^!\[')
  [ "$lines_count" -eq 2 ]
}

@test "--pr posts a comment via the gh stub; stdout stays clean" {
  GH_LOG="$TMP/gh.log"
  run env GH_STUB_LOG="$GH_LOG" bash "$SCRIPT" --pr 42 "$IMG"
  [ "$status" -eq 0 ]
  grep -q 'pr comment 42' "$GH_LOG"
}

# ---- bridge / dependency failure modes -------------------------------------

@test "bridge down is reported clearly" {
  run env CURL_STUB_UNHEALTHY=1 bash "$SCRIPT" "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bridge not reachable"* ]]
}

@test "missing bridge token is reported" {
  unset GHSHOT_BRIDGE_TOKEN
  run bash "$SCRIPT" "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no bridge token"* ]]
}

@test "a non-URL response from the bridge fails loudly" {
  run env CURL_STUB_BADRESP=1 bash "$SCRIPT" "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected response"* ]]
}

@test "gh auth failure is reported when resolving the repo" {
  run env GH_STUB_AUTH_FAIL=1 bash "$SCRIPT" "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not authenticated"* ]]
}

@test "--repo sets the target repo and needs no gh (no --pr)" {
  GH_LOG="$TMP/gh.log"
  run env GH_STUB_LOG="$GH_LOG" bash "$SCRIPT" --json --repo acme/widgets "$IMG"
  [ "$status" -eq 0 ]
  [ ! -f "$GH_LOG" ] # gh never invoked when --repo is given and not commenting
  [[ "$output" == *'"url":"https://github.com/user-attachments/assets/'* ]]
}

@test "--repo rejects a non owner/name value" {
  run bash "$SCRIPT" --repo "owner/name/extra" "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"owner/name form"* ]]
}

@test "--pr with --repo targets that repo in the gh comment" {
  GH_LOG="$TMP/gh.log"
  run env GH_STUB_LOG="$GH_LOG" bash "$SCRIPT" --repo acme/widgets --pr 7 "$IMG"
  [ "$status" -eq 0 ]
  grep -q 'pr comment 7 --repo acme/widgets' "$GH_LOG"
}

@test "--pr with no number targets the current branch's PR" {
  GH_LOG="$TMP/gh.log"
  run env GH_STUB_LOG="$GH_LOG" GH_STUB_PR=314 bash "$SCRIPT" --pr "$IMG"
  [ "$status" -eq 0 ]
  grep -q 'pr comment 314' "$GH_LOG"
}

@test "--pr without a number AND --repo (other repo) requires a number" {
  run bash "$SCRIPT" --repo acme/widgets --pr "$IMG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PR number is required"* ]]
}
