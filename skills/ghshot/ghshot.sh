#!/usr/bin/env bash
# ghshot — upload images to GitHub via your own logged-in browser session.
#
# Uploads through a Chrome extension + a tiny local bridge, using your EXISTING
# github.com session — no cookie extraction, no stored secret. The resulting
# github.com/user-attachments URL renders INLINE and is access-controlled to
# people who can see the repo (works on PRIVATE repos).
#
# Needs: the bridge running (bridge/ghshot-bridge) and the Chrome extension
# installed + signed in to github.com. See SKILL.md / README.md.
# Dependencies: curl + coreutils; gh only to resolve the current repo and to
# post --pr/--issue comments.
#
# Usage:
#   ghshot.sh [options] <image>...
#
# Options:
#   --pr N            upload all images, then post ONE comment on PR #N
#   --issue N         same, but on issue #N
#   --raw             print only the first raw URL (no markdown)
#   --json            print {"url","markdown","visibility"} (machine-readable)
#   --force, -f       skip the sensitive-filename / image-only / size guards
#   --version, -V     print version and exit
#   -h, --help        print this help and exit
#   --                end of options; treat the rest as file paths
#
# Environment:
#   GHSHOT_FORCE=1                skip content guards
#   GHSHOT_MAX_BYTES=N            max upload size in bytes (default 26214400 = 25 MiB)
#   GHSHOT_REPO=owner/name        repo to attach to (default: gh repo view in cwd)
#   GHSHOT_BRIDGE_URL=url          bridge base URL (default http://127.0.0.1:PORT)
#   GHSHOT_BRIDGE_PORT=41330       bridge port when GHSHOT_BRIDGE_URL is unset
#   GHSHOT_BRIDGE_TOKEN=hex        auth token (default: ~/.config/ghshot/bridge-token)
#
# The image is access-controlled to people who can see the repo. Even so, do not
# upload secrets: the content guards refuse sensitive filenames / non-images;
# --force bypasses them only when you are sure.
set -euo pipefail

VERSION="0.2.0"
MAX_BYTES_DEFAULT=26214400 # 25 MiB

die() {
  printf 'ghshot: %s\n' "$1" >&2
  exit 1
}

usage() {
  sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//; s/^#//'
}

# ---- defaults (env, then overridable by flags) ----
mode="markdown" # markdown | raw | json
target_kind=""  # pr | issue
target_num=""
force=0
files=()
[ "${GHSHOT_FORCE:-}" = 1 ] && force=1
max_bytes="${GHSHOT_MAX_BYTES:-$MAX_BYTES_DEFAULT}"

# ---- parse args ----
while [ $# -gt 0 ]; do
  case "$1" in
    --raw)
      mode="raw"
      shift
      ;;
    --json)
      mode="json"
      shift
      ;;
    --pr)
      target_kind="pr"
      target_num="${2:-}"
      shift 2 || shift
      ;;
    --issue)
      target_kind="issue"
      target_num="${2:-}"
      shift 2 || shift
      ;;
    --force | -f)
      force=1
      shift
      ;;
    --version | -V)
      printf 'ghshot %s\n' "$VERSION"
      exit 0
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        files+=("$1")
        shift
      done
      break
      ;;
    -*) die "unknown flag: $1 (see --help)" ;;
    *)
      files+=("$1")
      shift
      ;;
  esac
done

if [ -n "$target_kind" ]; then
  case "$target_num" in
    '' | *[!0-9]*) die "--$target_kind needs a number, e.g. --$target_kind 42" ;;
  esac
fi
[ "${#files[@]}" -gt 0 ] || die "no image given. usage: ghshot [options] <image>...  (see --help)"
case "$max_bytes" in '' | *[!0-9]*) die "GHSHOT_MAX_BYTES must be an integer, got: $max_bytes" ;; esac

# ---- bridge config (local bridge + browser extension) ----
bridge_port="${GHSHOT_BRIDGE_PORT:-41330}"
bridge_url="${GHSHOT_BRIDGE_URL:-http://127.0.0.1:$bridge_port}"
bridge_token="${GHSHOT_BRIDGE_TOKEN:-}"
if [ -z "$bridge_token" ] && [ -f "$HOME/.config/ghshot/bridge-token" ]; then
  bridge_token="$(cat "$HOME/.config/ghshot/bridge-token" 2>/dev/null || true)"
fi

# is the local bridge up? (no auth needed for /healthz)
bridge_healthy() {
  curl -fsS --max-time 2 "$bridge_url/healthz" >/dev/null 2>&1
}

# ---- dependency checks ----
command -v curl >/dev/null 2>&1 || die "curl not found — required by ghshot"

# gh is used to resolve the current repo (when GHSHOT_REPO is unset) and to post
# --pr/--issue comments.
need_gh=0
[ -z "${GHSHOT_REPO:-}" ] && need_gh=1
[ -n "$target_kind" ] && need_gh=1
if [ "$need_gh" = 1 ]; then
  command -v gh >/dev/null 2>&1 || die "gh CLI not found — install from https://cli.github.com"
  gh auth status >/dev/null 2>&1 || die "gh not authenticated — run: gh auth login"
fi

# refuse-by-default guard (enforced even for agents); --force / GHSHOT_FORCE overrides
vet_file() {
  local f="$1" base lc size
  base="$(basename -- "$f")"
  lc="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  [ "$force" = 1 ] && return 0
  case "$lc" in
    .env | .env.* | *.pem | *.key | *.pfx | *.p12 | *.kdbx | id_rsa* | id_dsa* | id_ecdsa* | id_ed25519* | .npmrc | .netrc | *.gpg | *.asc | *secret* | *credential* | *password*)
      die "refusing to upload sensitive-looking file: $base (override with --force)"
      ;;
  esac
  case "$lc" in
    *.png | *.jpg | *.jpeg | *.gif | *.webp | *.svg | *.bmp | *.apng | *.avif | *.tif | *.tiff | *.ico) : ;;
    *) die "not an image by extension: $base (override with --force)" ;;
  esac
  size="$(wc -c <"$f" | tr -d '[:space:]')"
  if [ "$size" -gt "$max_bytes" ]; then
    die "file too large: ${size}B > ${max_bytes}B (override with --force or set GHSHOT_MAX_BYTES)"
  fi
}

# Resolve the repo to attach to: GHSHOT_REPO, else `gh repo view` in the current dir.
resolve_repo() {
  local r
  r="${GHSHOT_REPO:-}"
  if [ -z "$r" ]; then
    r="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  fi
  [ -n "$r" ] || die "could not resolve repo — set GHSHOT_REPO=owner/name or run inside a git repo with a GitHub remote"
  printf '%s' "$r"
}

# Upload one image through the bridge -> extension -> your github.com session.
attach_repo=""
upload_one() {
  local path="$1" url
  [ -f "$path" ] || die "file not found: $path"
  vet_file "$path"
  [ -n "$bridge_token" ] || die "no bridge token found — set GHSHOT_BRIDGE_TOKEN or start the bridge to create ~/.config/ghshot/bridge-token (run: bridge/ghshot-bridge --print-token)"
  bridge_healthy || die "ghshot bridge not reachable at $bridge_url — start it (run: bridge/ghshot-bridge) and keep Chrome open with the ghshot extension installed and signed in to github.com"
  [ -n "$attach_repo" ] || attach_repo="$(resolve_repo)"
  url="$(curl -fsS -H "X-Ghshot-Token: $bridge_token" \
    -F repo="$attach_repo" -F file=@"$path" \
    "$bridge_url/v1/upload?format=text")" ||
    die "upload failed via $bridge_url — is Chrome open and signed in to github.com, with the ghshot extension installed and configured with this bridge URL/token?"
  url="$(printf '%s' "$url" | tr -d '[:space:]')"
  case "$url" in
    https://*) ;;
    *) die "the bridge returned an unexpected response (not a URL)" ;;
  esac
  printf '%s' "$url"
}

# ---- upload everything, build markdown (always inline) ----
md=""
first_url=""
for f in "${files[@]}"; do
  url="$(upload_one "$f")"
  [ -n "$first_url" ] || first_url="$url"
  alt="$(basename -- "$f")"
  alt="${alt%.*}"
  [ -n "$alt" ] || alt="image"
  md+="![${alt}](${url})"$'\n'
done
md="${md%$'\n'}"

# JSON-escape a string (preserves newlines as \n). Pure bash (3.2-safe) — avoids the
# BSD/GNU `sed N` slurp difference that drops single-line input on macOS.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}" # backslash -> \\
  s="${s//\"/\\\"}" # quote     -> \"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

# ---- post a comment, or print ----
if [ -n "$target_kind" ]; then
  printf '%s\n' "$md" | gh "$target_kind" comment "$target_num" --body-file - >&2 ||
    die "failed to comment on $target_kind #$target_num"
  printf 'ghshot: commented on %s #%s\n' "$target_kind" "$target_num" >&2
  exit 0
fi

case "$mode" in
  raw) printf '%s\n' "$first_url" ;;
  json)
    printf '{"url":"%s","markdown":"%s","visibility":"private"}\n' \
      "$(json_escape "$first_url")" "$(json_escape "$md")"
    ;;
  *) printf '%s\n' "$md" ;;
esac
