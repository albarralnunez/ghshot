#!/usr/bin/env bash
# ghshot — upload images to GitHub, get markdown-ready URLs for PRs/issues/comments.
#
# Core is dependency-free: needs only `gh` (authenticated) + coreutils. No node, no npm.
# Two hosting backends:
#   attachments  THE marquee backend: TRUE private + inline. Uploads through your OWN
#                logged-in github.com browser session via a local bridge + a Chrome
#                extension (no cookie extraction, no stored secret). The resulting
#                github.com/user-attachments URL renders INLINE and is access-controlled
#                to people who can see the repo — works on PRIVATE repos. Auto-selected
#                when the local bridge is running. Needs the bridge + extension; see
#                SKILL.md. No extra hosting repo.
#   release      GitHub release asset on <you>/ghshot-images. PRIVATE by default.
#                Private GitHub assets do NOT render inline (GitHub won't proxy them), so a
#                private upload is emitted as a LINK. Use --public for an inline-rendering repo.
#                A public release URL is unguessable but NOT access-controlled.
#
# attachments is the only backend with a TRUE access-control list (the repo's ACL).
#
# Usage:
#   ghshot.sh [options] <image>...
#
# Options:
#   --pr N            upload all images, then post ONE comment on PR #N
#   --issue N         same, but on issue #N
#   --backend NAME    attachments | release
#                     (auto: attachments if the bridge is up, else release)
#   --public          release backend only: host on a PUBLIC repo (needed for inline images)
#   --private         force private (default); kept for explicitness
#   --raw             print only the first raw URL (no markdown)
#   --json            print {"url","markdown","backend","visibility"} (machine-readable)
#   --force, -f       skip the sensitive-filename / image-only / size guards
#   --yes, -y         skip the interactive "create repo?" confirmation
#   --version, -V     print version and exit
#   -h, --help        print this help and exit
#   --                end of options; treat the rest as file paths
#
# Environment:
#   GHSHOT_BACKEND=attachments|release   default backend
#   GHSHOT_PUBLIC=1             default to a public release repo
#   GHSHOT_FORCE=1             skip content guards
#   GHSHOT_ASSUME_YES=1        skip the create-repo confirmation
#   GHSHOT_MAX_BYTES=N         max upload size in bytes (default 26214400 = 25 MiB)
#   attachments backend:
#     GHSHOT_REPO=owner/name       repo to attach to (default: gh repo view in cwd)
#     GHSHOT_BRIDGE_URL=url         bridge base URL (default http://127.0.0.1:PORT)
#     GHSHOT_BRIDGE_PORT=41330      bridge port when GHSHOT_BRIDGE_URL is unset
#     GHSHOT_BRIDGE_TOKEN=hex       auth token (default: ~/.config/ghshot/bridge-token)
#
# SECURITY: a public release URL is unguessable but NOT access-controlled — anyone with
#           the link can view it. Do not upload secrets. Use --force to bypass the guards
#           only when you are sure.
set -euo pipefail

VERSION="0.1.0"
TAG="_ghshot"
IMAGE_REPO="ghshot-images"
MAX_BYTES_DEFAULT=26214400 # 25 MiB

die() {
  printf 'ghshot: %s\n' "$1" >&2
  exit 1
}

usage() {
  sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//; s/^#//'
}

# ---- defaults (env, then overridable by flags) ----
mode="markdown" # markdown | raw | json
target_kind=""  # pr | issue
target_num=""
backend="${GHSHOT_BACKEND:-}"
visibility="private" # release backend default
assume_yes=0
force=0
files=()
[ "${GHSHOT_PUBLIC:-}" = 1 ] && visibility="public"
[ "${GHSHOT_ASSUME_YES:-}" = 1 ] && assume_yes=1
[ "${GHSHOT_FORCE:-}" = 1 ] && force=1
max_bytes="${GHSHOT_MAX_BYTES:-$MAX_BYTES_DEFAULT}"

# ---- parse args ----
while [ $# -gt 0 ]; do
  case "$1" in
    --raw) mode="raw"; shift ;;
    --json) mode="json"; shift ;;
    --pr) target_kind="pr"; target_num="${2:-}"; shift 2 || shift ;;
    --issue) target_kind="issue"; target_num="${2:-}"; shift 2 || shift ;;
    --backend) backend="${2:-}"; shift 2 || shift ;;
    --public) visibility="public"; shift ;;
    --private) visibility="private"; shift ;;
    --force | -f) force=1; shift ;;
    --yes | -y) assume_yes=1; shift ;;
    --version | -V) printf 'ghshot %s\n' "$VERSION"; exit 0 ;;
    -h | --help) usage; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do files+=("$1"); shift; done; break ;;
    -*) die "unknown flag: $1 (see --help)" ;;
    *) files+=("$1"); shift ;;
  esac
done

# ---- attachments backend config (local bridge + browser extension) ----
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

# auto-precedence: explicit --backend / GHSHOT_BACKEND wins; else attachments if the
# bridge is running; else release.
if [ -z "$backend" ]; then
  if bridge_healthy; then
    backend="attachments"
  else
    backend="release"
  fi
fi
case "$backend" in attachments | release) ;; *) die "unknown backend: $backend (use attachments|release)" ;; esac

if [ -n "$target_kind" ]; then
  case "$target_num" in
    '' | *[!0-9]*) die "--$target_kind needs a number, e.g. --$target_kind 42" ;;
  esac
fi
[ "${#files[@]}" -gt 0 ] || die "no image given. usage: ghshot [options] <image>...  (see --help)"
case "$max_bytes" in '' | *[!0-9]*) die "GHSHOT_MAX_BYTES must be an integer, got: $max_bytes" ;; esac

# ---- gh is needed for the release backend, for posting comments, and to resolve the
#      current repo for the attachments backend when GHSHOT_REPO is not set ----
need_gh=0
[ "$backend" = release ] && need_gh=1
[ "$backend" = attachments ] && [ -z "${GHSHOT_REPO:-}" ] && need_gh=1
[ -n "$target_kind" ] && need_gh=1
if [ "$need_gh" = 1 ]; then
  command -v gh >/dev/null 2>&1 || die "gh CLI not found — install from https://cli.github.com"
  gh auth status >/dev/null 2>&1 || die "gh not authenticated — run: gh auth login"
fi

# attachments needs curl (to reach the local bridge)
[ "$backend" = attachments ] && {
  command -v curl >/dev/null 2>&1 || die "curl not found — required for --backend attachments"
}

# ---- temp workspace, always cleaned up ----
WORKDIR=""
cleanup() { [ -n "$WORKDIR" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT INT TERM
WORKDIR="$(mktemp -d)"

# long unguessable token (~96 bits) — the obscurity in "security by obscurity"
rand_token() {
  openssl rand -hex 12 2>/dev/null \
    || printf '%04x%04x%04x%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
}

# refuse-by-default guard (enforced even for agents); --force / GHSHOT_FORCE overrides
vet_file() {
  local f="$1" base lc size
  base="$(basename -- "$f")"
  lc="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  [ "$force" = 1 ] && return 0
  case "$lc" in
    .env | .env.* | *.pem | *.key | *.pfx | *.p12 | *.kdbx | id_rsa* | id_dsa* | id_ecdsa* | id_ed25519* | .npmrc | .netrc | *.gpg | *.asc | *secret* | *credential* | *password*)
      die "refusing to upload sensitive-looking file: $base (override with --force)" ;;
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

# safe, GitHub-stable asset name: <stem>-<token>.<ext>, restricted charset
asset_name() {
  local base="$1" ext stem raw
  case "$base" in *.*) ext=".${base##*.}" ;; *) ext="" ;; esac
  stem="${base%.*}"; [ -n "$stem" ] || stem="image"
  raw="${stem}-$(rand_token)${ext}"
  printf '%s' "$raw" | LC_ALL=C tr -c 'A-Za-z0-9._-' '-'
}

# ---- release backend (GitHub release asset) ----
release_repo=""
ensure_release_repo() {
  [ -z "$release_repo" ] || return 0
  local user visflag visname cur branch readme
  user="$(gh api user -q .login)" || die "could not resolve gh user (is gh authenticated?)"
  release_repo="$user/$IMAGE_REPO"
  if [ "$visibility" = public ]; then visflag="--public"; visname="PUBLIC"; else visflag="--private"; visname="PRIVATE"; fi

  if gh repo view "$release_repo" >/dev/null 2>&1; then
    cur="$(gh repo view "$release_repo" --json visibility -q .visibility 2>/dev/null || echo UNKNOWN)"
    if [ "$visibility" = public ] && [ "$cur" != "PUBLIC" ]; then
      printf 'ghshot: WARNING: %s exists and is %s, not public — inline images may not render.\n' "$release_repo" "$cur" >&2
    fi
    branch="$(gh repo view "$release_repo" --json defaultBranchRef -q '.defaultBranchRef.name // ""' 2>/dev/null || true)"
    [ -n "$branch" ] && return 0
  else
    if [ "$assume_yes" != 1 ] && [ -t 0 ] && [ -t 2 ]; then
      printf 'ghshot: create %s repo %s to host images? [y/N] ' "$visname" "$release_repo" >&2
      local ans; read -r ans </dev/tty || ans=""
      case "$ans" in y | Y | yes | YES) ;; *) die "aborted (use --yes / GHSHOT_ASSUME_YES=1 to skip)" ;; esac
    fi
    printf 'ghshot: creating %s repo %s for image hosting...\n' "$visname" "$release_repo" >&2
    gh repo create "$release_repo" "$visflag" \
      --description "Image hosting for GitHub issues & PRs. Managed by ghshot." >/dev/null 2>&1 \
      || gh repo view "$release_repo" >/dev/null 2>&1 \
      || die "could not create $release_repo (manual: gh repo create $IMAGE_REPO $visflag)"
  fi
  readme="$(printf '# %s\n\nImage hosting for GitHub issues & PRs. Managed by ghshot.\n' "$IMAGE_REPO" | base64 | tr -d '\n')"
  gh api "repos/$release_repo/contents/README.md" --method PUT \
    -f message="Initial commit" -f content="$readme" >/dev/null \
    || die "could not initialize $release_repo (needs one commit before releases work)"
}

release_release_ready=0
release_upload() {
  local path="$1" name tmp
  ensure_release_repo
  if [ "$release_release_ready" != 1 ]; then
    gh release view "$TAG" --repo "$release_repo" >/dev/null 2>&1 \
      || gh release create "$TAG" --repo "$release_repo" \
        --title "ghshot uploads" \
        --notes "Image hosting managed by ghshot. Do not delete this release." >/dev/null 2>&1 \
      || gh release view "$TAG" --repo "$release_repo" >/dev/null 2>&1 \
      || die "could not create release '$TAG' on $release_repo (need write access)"
    release_release_ready=1
  fi
  name="$(asset_name "$(basename -- "$path")")"
  tmp="$WORKDIR/$name"
  cp -- "$path" "$tmp"
  gh release upload "$TAG" "$tmp" --repo "$release_repo" --clobber >/dev/null 2>&1 \
    || die "upload failed for $path"
  rm -f "$tmp"
  printf 'https://github.com/%s/releases/download/%s/%s' "$release_repo" "$TAG" "$name"
}

# ---- attachments backend (user's own github.com session via local bridge + extension) ----
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

attachments_repo=""
attachments_upload() {
  local path="$1" url
  [ -n "$bridge_token" ] || die "no bridge token found — set GHSHOT_BRIDGE_TOKEN or start the bridge to create ~/.config/ghshot/bridge-token (run: bridge/ghshot-bridge --print-token)"
  bridge_healthy || die "ghshot bridge not reachable at $bridge_url — start it (run: bridge/ghshot-bridge) and keep Chrome open with the ghshot extension installed"
  [ -n "$attachments_repo" ] || attachments_repo="$(resolve_repo)"
  # POST the image to the bridge; it relays to the extension, which uploads via your
  # logged-in github.com session and returns the inline user-attachments URL.
  url="$(curl -fsS -H "X-Ghshot-Token: $bridge_token" \
    -F repo="$attachments_repo" -F file=@"$path" \
    "$bridge_url/v1/upload?format=text")" \
    || die "attachments upload failed via $bridge_url — is Chrome open and signed in to github.com, with the ghshot extension installed and configured with this bridge URL/token?"
  url="$(printf '%s' "$url" | tr -d '[:space:]')"
  case "$url" in
    https://*) ;;
    *) die "attachments: bridge returned an unexpected response (not a URL)" ;;
  esac
  printf '%s' "$url"
}

upload_one() {
  local path="$1"
  [ -f "$path" ] || die "file not found: $path"
  vet_file "$path"
  case "$backend" in
    attachments) attachments_upload "$path" ;;
    release) release_upload "$path" ;;
  esac
}

# inline rendering: everything renders inline EXCEPT a private GitHub release asset
# (attachments renders inline and is access-controlled; private release is a link)
inline=1
[ "$backend" = release ] && [ "$visibility" = private ] && inline=0

# ---- upload everything, build markdown ----
md=""; first_url=""
for f in "${files[@]}"; do
  url="$(upload_one "$f")"
  [ -n "$first_url" ] || first_url="$url"
  alt="$(basename -- "$f")"; alt="${alt%.*}"; [ -n "$alt" ] || alt="image"
  if [ "$inline" = 1 ]; then md+="![${alt}](${url})"$'\n'; else md+="[${alt}](${url})"$'\n'; fi
done
md="${md%$'\n'}"

[ "$inline" = 1 ] || printf 'ghshot: note: private GitHub uploads render as a LINK, not an inline image (use --public, or the attachments backend for inline).\n' >&2

# JSON-escape a string (preserves newlines as \n)
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

vis_label() {
  case "$backend" in
    attachments) printf 'private' ;; # TRUE ACL: only people who can see the repo
    *) printf '%s' "$visibility" ;;
  esac
}

# ---- post a comment, or print ----
if [ -n "$target_kind" ]; then
  printf '%s\n' "$md" | gh "$target_kind" comment "$target_num" --body-file - >&2 \
    || die "failed to comment on $target_kind #$target_num"
  printf 'ghshot: commented on %s #%s\n' "$target_kind" "$target_num" >&2
  exit 0
fi

case "$mode" in
  raw) printf '%s\n' "$first_url" ;;
  json)
    printf '{"url":"%s","markdown":"%s","backend":"%s","visibility":"%s"}\n' \
      "$(json_escape "$first_url")" "$(json_escape "$md")" "$backend" "$(vis_label)" ;;
  *) printf '%s\n' "$md" ;;
esac
