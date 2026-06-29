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
#   --pr [N]          upload all images, then post ONE comment on PR #N
#                     (no number → the current branch's PR)
#   --issue N         same, but on issue #N
#   --pick            interactively pick the repo + PR as the target (needs fzf)
#   --repo OWNER/NAME target repo for the attachment AND the --pr/--issue comment
#                     (default: GHSHOT_REPO, else `gh repo view` in the cwd)
#   --raw             print only the first raw URL (no markdown)
#   --json            print {"url","markdown"} (machine-readable)
#   --force, -f       skip the sensitive-filename / image-only / size guards
#   --version, -V     print version and exit
#   -h, --help        print this help and exit
#   --                end of options; treat the rest as file paths
#
# Environment:
#   GHSHOT_FORCE=1                skip content guards
#   GHSHOT_MAX_BYTES=N            max upload size in bytes (default 26214400 = 25 MiB)
#   GHSHOT_REPO=owner/name        default repo (overridden by --repo; else gh repo view in cwd)
#   GHSHOT_BRIDGE_URL=url          bridge base URL (default http://127.0.0.1:PORT)
#   GHSHOT_BRIDGE_PORT=41330       bridge port when GHSHOT_BRIDGE_URL is unset
#   GHSHOT_BRIDGE_TOKEN=hex        auth token (default: ~/.config/ghshot/bridge-token)
#
# The image is access-controlled to people who can see the repo. Even so, do not
# upload secrets: the content guards refuse sensitive filenames / non-images;
# --force bypasses them only when you are sure.
set -euo pipefail

VERSION="0.6.0"
MAX_BYTES_DEFAULT=26214400 # 25 MiB

die() {
  printf 'ghshot: %s\n' "$1" >&2
  exit 1
}

usage() {
  sed -n '2,41p' "$0" | sed 's/^# \{0,1\}//; s/^#//'
}

# owner/name shape + character-class validation. Applied to BOTH --repo and the
# resolved repo (GHSHOT_REPO / `gh repo view`), so an env-supplied value is
# validated identically and never carries `;`/odd characters into curl/gh.
validate_repo() {
  local r="$1" what="${2:-repo}"
  case "$r" in
    */*/* | /* | */) die "$what must be in owner/name form" ;;
    */*) ;;
    *) die "$what must be in owner/name form" ;;
  esac
  case "$r" in *[!A-Za-z0-9._/-]*) die "$what has invalid characters (expected owner/name)" ;; esac
}

# Best-effort MIME from the extension (the bytes are sent over stdin, so the
# filename/type are set explicitly rather than parsed by curl from the path).
mime_for() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *.png) printf 'image/png' ;;
    *.jpg | *.jpeg) printf 'image/jpeg' ;;
    *.gif) printf 'image/gif' ;;
    *.webp) printf 'image/webp' ;;
    *.svg) printf 'image/svg+xml' ;;
    *.bmp) printf 'image/bmp' ;;
    *.apng) printf 'image/apng' ;;
    *.avif) printf 'image/avif' ;;
    *.tif | *.tiff) printf 'image/tiff' ;;
    *.ico) printf 'image/x-icon' ;;
    *) printf 'application/octet-stream' ;;
  esac
}

# Escape Markdown metacharacters in image alt text so an adversarial filename
# cannot inject links/images into a posted comment (and so benign filenames
# containing []() render correctly).
md_escape() {
  local s="$1"
  s="${s//$'\r'/}"
  s="${s//$'\n'/ }"
  s="${s//\\/\\\\}"
  s="${s//\`/\\\`}"
  s="${s//\[/\\[}"
  s="${s//\]/\\]}"
  s="${s//(/\\(}"
  s="${s//)/\\)}"
  printf '%s' "$s"
}

# ---- defaults (env, then overridable by flags) ----
mode="markdown" # markdown | raw | json
target_kind=""  # pr | issue
target_num=""
repo_opt=""
pick=0
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
      # number is optional: consume the next token only if it is numeric
      case "${2:-}" in
        '' | *[!0-9]*) shift ;;
        *)
          target_num="$2"
          shift 2
          ;;
      esac
      ;;
    --issue)
      target_kind="issue"
      case "${2:-}" in
        '' | *[!0-9]*) shift ;;
        *)
          target_num="$2"
          shift 2
          ;;
      esac
      ;;
    --repo)
      [ $# -ge 2 ] || die "--repo needs a value (owner/name)"
      case "$2" in -*) die "--repo needs a value (owner/name), got: $2" ;; esac
      repo_opt="$2"
      shift 2
      ;;
    --pick)
      pick=1
      shift
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

# A number (when given) must be numeric; an empty number is resolved later
# (--pick, or auto-detect the current branch's PR for --pr).
if [ -n "$target_num" ]; then
  case "$target_num" in *[!0-9]*) die "--$target_kind number must be numeric, got: $target_num" ;; esac
fi
[ "${#files[@]}" -gt 0 ] || die "no image given. usage: ghshot [options] <image>...  (see --help)"
case "$max_bytes" in '' | *[!0-9]*) die "GHSHOT_MAX_BYTES must be an integer, got: $max_bytes" ;; esac
if [ -n "$repo_opt" ]; then
  validate_repo "$repo_opt" "--repo"
fi

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
[ -z "$repo_opt" ] && [ -z "${GHSHOT_REPO:-}" ] && need_gh=1
[ -n "$target_kind" ] && need_gh=1
[ "$pick" = 1 ] && need_gh=1
[ "$pick" = 1 ] && [ -z "$target_num" ] && need_gh=1
if [ "$need_gh" = 1 ]; then
  command -v gh >/dev/null 2>&1 || die "gh CLI not found — install from https://cli.github.com"
  gh auth status >/dev/null 2>&1 || die "gh not authenticated — run: gh auth login"
fi
# --pick is interactive (needs fzf + a terminal)
if [ "$pick" = 1 ]; then
  command -v fzf >/dev/null 2>&1 || die "--pick needs fzf"
fi

# Best-effort, FILENAME-based sensitive-name denylist (not content inspection).
# Returns 0 if the lowercased basename looks sensitive.
sensitive_name() {
  case "$1" in
    .env | .env.* | *.pem | *.key | *.pfx | *.p12 | *.kdbx | id_rsa* | id_dsa* | id_ecdsa* | id_ed25519* | .npmrc | .netrc | *.gpg | *.asc | *secret* | *credential* | *password*)
      return 0
      ;;
  esac
  return 1
}

# refuse-by-default guard (enforced even for agents); --force / GHSHOT_FORCE overrides.
# NOTE: this is a best-effort accidental-upload guard based on the FILENAME (and a
# symlink's resolved target) — it does not inspect file contents.
vet_file() {
  local f="$1" base lc size tgt tlc
  base="$(basename -- "$f")"
  lc="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  [ "$force" = 1 ] && return 0
  if sensitive_name "$lc"; then
    die "refusing to upload sensitive-looking file: $base (override with --force)"
  fi
  # A symlink named innocuously (pic.png) can point at a secret (~/.ssh/id_rsa);
  # re-check the resolved target's name too.
  if [ -L "$f" ]; then
    tgt="$(readlink -f -- "$f" 2>/dev/null || true)"
    if [ -n "$tgt" ]; then
      tlc="$(printf '%s' "$(basename -- "$tgt")" | tr '[:upper:]' '[:lower:]')"
      if sensitive_name "$tlc"; then
        die "refusing to upload: symlink '$base' points at a sensitive-looking file: $tgt (override with --force)"
      fi
    fi
  fi
  case "$lc" in
    *.png | *.jpg | *.jpeg | *.gif | *.webp | *.svg | *.bmp | *.apng | *.avif | *.tif | *.tiff | *.ico) : ;;
    *) die "not an image by extension: $base (override with --force)" ;;
  esac
  size="$(wc -c <"$f" | tr -d '[:space:]')"
  if [ "$size" -gt "$max_bytes" ]; then
    die "file too large: ${size}B > ${max_bytes}B (override with --force or set GHSHOT_MAX_BYTES)"
  fi
}

# Resolve the repo to attach to: --repo > GHSHOT_REPO > `gh repo view` (cwd) >
# (with --pick) an fzf picker over your repos.
resolve_repo() {
  local r
  r="${repo_opt:-${GHSHOT_REPO:-}}"
  if [ -z "$r" ]; then
    r="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  fi
  if [ -z "$r" ] && [ "$pick" = 1 ]; then
    r="$(gh repo list --limit 200 --json nameWithOwner -q '.[].nameWithOwner' 2>/dev/null |
      fzf --prompt='repo> ' --height=40% --reverse || true)"
  fi
  [ -n "$r" ] || die "could not resolve repo — pass --repo owner/name, set GHSHOT_REPO, run inside a git repo, or use --pick"
  # Validate the resolved value too (covers GHSHOT_REPO / gh repo view, not just --repo).
  validate_repo "$r" "repo"
  printf '%s' "$r"
}

# Resolve the comment target (PR/issue number) when it wasn't given explicitly:
#  --pick           -> fzf-choose an open PR of the repo
#  --pr (no number) -> the current branch's PR (resolved by gh in the cwd)
resolve_target() {
  if [ "$pick" = 1 ] && [ -z "$target_num" ]; then
    local sel
    sel="$(gh pr list --repo "$attach_repo" --state open --limit 100 \
      --json number,title,headRefName -q '.[] | "#\(.number)\t\(.headRefName)\t\(.title)"' 2>/dev/null |
      fzf --delimiter='\t' --with-nth=1,2,3 --height=60% --reverse \
        --prompt="PR @ $attach_repo > ")" || true
    [ -n "$sel" ] || die "no PR selected"
    target_kind="pr"
    sel="${sel%%	*}"
    target_num="${sel#\#}"
  fi
  [ -n "$target_kind" ] || return 0
  if [ -z "$target_num" ]; then
    case "$target_kind" in
      pr)
        [ -z "$repo_opt" ] || die "a PR number is required with --repo (or use --pick)"
        target_num="$(gh pr view --json number -q .number 2>/dev/null || true)"
        [ -n "$target_num" ] || die "no PR found for the current branch — pass --pr N or use --pick"
        ;;
      issue) die "--issue needs a number (or use --pick to choose a PR)" ;;
    esac
  fi
}

# Upload one image through the bridge -> extension -> your github.com session.
attach_repo=""
hdr_file=""
upload_one() {
  local path="$1" url base safebase mime rest host
  [ -f "$path" ] || die "file not found: $path"
  vet_file "$path"
  [ -n "$bridge_token" ] || die "no bridge token found — set GHSHOT_BRIDGE_TOKEN or start the bridge to create ~/.config/ghshot/bridge-token (run: bridge/ghshot-bridge --print-token)"
  bridge_healthy || die "ghshot bridge not reachable at $bridge_url — start it (run: bridge/ghshot-bridge) and keep Chrome open with the ghshot extension installed and signed in to github.com"
  # Send the bytes over stdin (@-) so the file path never reaches curl's -F
  # @-parser (which would reinterpret ';type='/';headers=' in a crafted path and
  # could read a different file than the one vetted). Set a clean filename/type
  # explicitly. The token goes via a 0600 header file, never argv (/proc/<pid>).
  base="$(basename -- "$path")"
  safebase="${base//;/_}"
  safebase="${safebase//\"/_}"
  safebase="${safebase//$'\r'/_}"
  safebase="${safebase//$'\n'/_}"
  mime="$(mime_for "$base")"
  url="$(curl -fsS -H @"$hdr_file" \
    -F "repo=$attach_repo" \
    -F "file=@-;filename=$safebase;type=$mime" \
    "$bridge_url/v1/upload?format=text" <"$path")" ||
    die "upload failed via $bridge_url — is Chrome open and signed in to github.com, with the ghshot extension installed and configured with this bridge URL/token?"
  url="$(printf '%s' "$url" | tr -d '[:space:]')"
  # Reject control chars (terminal/log-escape) and Markdown-breaking
  # metacharacters, then require a GitHub attachment URL (the value is
  # interpolated into a comment posted under your identity and printed to a TTY).
  case "$url" in
    *[[:cntrl:]]*) die "the bridge returned an unexpected response (control characters)" ;;
    *'('* | *')'* | *'['* | *']'* | *'`'*) die "the bridge returned an unexpected response (bad URL)" ;;
  esac
  rest="${url#https://}"
  host="${rest%%[/?#]*}"
  case "$url" in
    https://github.com/user-attachments/assets/*) ;;
    *)
      case "$host" in
        *.githubusercontent.com) ;;
        *) die "the bridge returned an unexpected response (not a GitHub attachment URL)" ;;
      esac
      ;;
  esac
  printf '%s' "$url"
}

# Resolve the target repo once in the parent shell — upload_one runs inside a
# $() subshell, so resolving there would not persist, and the --pr/--issue
# comment below needs it too. Then resolve the PR/issue target (pick/auto).
attach_repo="$(resolve_repo)"
resolve_target

# A target number resolved indirectly (e.g. via --pick) must still be numeric.
if [ -n "$target_num" ]; then
  case "$target_num" in *[!0-9]*) die "resolved target number is not numeric: $target_num" ;; esac
fi

# Pass the bridge token to curl via a 0600 temp file referenced with `-H @file`,
# never on the command line (argv is world-readable via /proc/<pid>/cmdline).
# Created once in the parent shell (upload_one runs in a $() subshell). Register
# the cleanup trap BEFORE creating the file so there is no leftover-token window.
trap 'rm -f "$hdr_file" 2>/dev/null || true' EXIT
if [ -n "$bridge_token" ]; then
  hdr_file="$(mktemp "${TMPDIR:-/tmp}/ghshot.XXXXXX")" || die "could not create a temp file"
  chmod 600 "$hdr_file"
  printf 'X-Ghshot-Token: %s\n' "$bridge_token" >"$hdr_file"
fi

# ---- upload everything, build markdown (always inline) ----
md=""
first_url=""
for f in "${files[@]}"; do
  url="$(upload_one "$f")"
  [ -n "$first_url" ] || first_url="$url"
  alt="$(basename -- "$f")"
  alt="${alt%.*}"
  [ -n "$alt" ] || alt="image"
  alt="$(md_escape "$alt")"
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
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  # Escape any remaining C0 control characters as \u00XX (required by JSON).
  case "$s" in
    *[$'\x01'-$'\x1f']*)
      local out="" c i
      for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in
          [$'\x01'-$'\x1f']) printf -v c '\\u%04x' "'$c" ;;
        esac
        out+="$c"
      done
      s="$out"
      ;;
  esac
  printf '%s' "$s"
}

# ---- post a comment, or print ----
if [ -n "$target_kind" ]; then
  # attach_repo was resolved during the upload(s); target the same repo for the
  # comment so --pr/--issue work from any directory.
  printf '%s\n' "$md" | gh "$target_kind" comment "$target_num" --repo "$attach_repo" --body-file - >&2 ||
    die "failed to comment on $target_kind #$target_num (repo $attach_repo)"
  printf 'ghshot: commented on %s #%s (%s)\n' "$target_kind" "$target_num" "$attach_repo" >&2
  exit 0
fi

case "$mode" in
  raw) printf '%s\n' "$first_url" ;;
  json)
    printf '{"url":"%s","markdown":"%s"}\n' \
      "$(json_escape "$first_url")" "$(json_escape "$md")"
    ;;
  *) printf '%s\n' "$md" ;;
esac
