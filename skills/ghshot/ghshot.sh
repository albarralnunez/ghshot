#!/usr/bin/env bash
# ghshot — upload images to GitHub, get markdown-ready URLs for PRs/issues/comments.
#
# Dependency-free: needs only `gh` (authenticated) + standard coreutils. No node, no npm.
# Reimplements the GitHub-release backend of gitshot (https://github.com/vipulgupta2048/gitshot):
# images are stored as release assets on a dedicated PUBLIC repo <you>/ghshot-images,
# giving permanent CDN-backed URLs that render in any GitHub markdown context.
#
# Usage:
#   ghshot.sh [--raw|--json] [--pr N | --issue N] <image>...
#
#   ghshot.sh shot.png                 # print  ![shot](https://.../shot-ab12cd34.png)
#   ghshot.sh --raw shot.png           # print the raw URL only
#   ghshot.sh --json shot.png          # {"url":"...","markdown":"...","backend":"release"}
#   ghshot.sh --pr 42 before.png after.png   # upload all + post one comment on PR #42
#   ghshot.sh --issue 10 bug.png       # upload + comment on issue #10
#
# WARNING: ghshot-images is PUBLIC. Anyone with the URL can view uploads.
#          Do not upload sensitive images (credentials, internal dashboards, private data).
set -euo pipefail

TAG="_ghshot"
IMAGE_REPO="ghshot-images"

die() { printf 'ghshot: %s\n' "$1" >&2; exit 1; }

# ---- parse args ----
mode="markdown"     # markdown | raw | json
target_kind=""      # pr | issue
target_num=""
files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --raw)     mode="raw"; shift ;;
    --json)    mode="json"; shift ;;
    --pr)      target_kind="pr";    target_num="${2:-}"; shift 2 || shift ;;
    --issue)   target_kind="issue"; target_num="${2:-}"; shift 2 || shift ;;
    -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^#\{1,\} \{0,1\}//; s/^#//'; exit 0 ;;
    --)        shift; while [ $# -gt 0 ]; do files+=("$1"); shift; done; break ;;
    -*)        die "unknown flag: $1" ;;
    *)         files+=("$1"); shift ;;
  esac
done
if [ -n "$target_kind" ]; then
  case "$target_num" in
    ''|*[!0-9]*) die "--$target_kind needs a number, e.g. --$target_kind 42" ;;
  esac
fi
[ "${#files[@]}" -gt 0 ] || die "no image given. usage: ghshot [--raw|--json] [--pr N|--issue N] <image>..."

command -v gh >/dev/null 2>&1 || die "gh CLI not found — install from https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh not authenticated — run: gh auth login"

user="$(gh api user -q .login)" || die "could not resolve gh user (is gh authenticated?)"
repo="$user/$IMAGE_REPO"

# ---- ensure the image repo exists AND has a commit (releases need >=1 commit) ----
branch="$(gh repo view "$repo" --json defaultBranchRef -q '.defaultBranchRef.name // ""' 2>/dev/null || true)"
if [ -z "$branch" ]; then
  if ! gh repo view "$repo" >/dev/null 2>&1; then
    printf 'ghshot: creating %s for image hosting...\n' "$repo" >&2
    gh repo create "$repo" --public \
      --description "Image hosting for GitHub issues & PRs. Managed by ghshot." >/dev/null 2>&1 \
      || die "could not create $repo (create it manually: gh repo create $IMAGE_REPO --public)"
  fi
  readme="$(printf '# %s\n\nImage hosting for GitHub issues & PRs.\n' "$IMAGE_REPO" | base64 | tr -d '\n')"
  gh api "repos/$repo/contents/README.md" --method PUT \
    -f message="Initial commit" -f content="$readme" >/dev/null \
    || die "could not initialize $repo (it needs one commit before releases work)"
fi

# ---- ensure the holding release exists ----
if ! gh release view "$TAG" --repo "$repo" >/dev/null 2>&1; then
  gh release create "$TAG" --repo "$repo" \
    --title "ghshot uploads" \
    --notes "Image hosting managed by ghshot. Do not delete this release." \
    --latest=false >/dev/null 2>&1 \
    || die "could not create release '$TAG' on $repo (need write access)"
fi

rand8() { openssl rand -hex 4 2>/dev/null || printf '%04x%04x' "$RANDOM" "$RANDOM"; }

# upload one file, echo its download URL
upload_one() {
  local path="$1" base ext stem name dir tmp asset
  [ -f "$path" ] || die "file not found: $path"
  base="$(basename "$path")"
  case "$base" in *.*) ext=".${base##*.}" ;; *) ext="" ;; esac
  stem="${base%.*}"
  name="${stem}-$(rand8)${ext}"
  dir="$(mktemp -d)"; tmp="$dir/$name"
  cp "$path" "$tmp"
  gh release upload "$TAG" "$tmp" --repo "$repo" --clobber >/dev/null 2>&1 \
    || { rm -rf "$dir"; die "upload failed for $path"; }
  rm -rf "$dir"
  asset="${name// /.}"   # GitHub turns spaces into dots in asset names
  printf 'https://github.com/%s/releases/download/%s/%s' "$repo" "$TAG" "$asset"
}

# ---- upload everything, build markdown ----
md=""; first_url=""
for f in "${files[@]}"; do
  url="$(upload_one "$f")"
  [ -n "$first_url" ] || first_url="$url"
  alt="$(basename "$f")"; alt="${alt%.*}"
  md+="![${alt}](${url})"$'\n'
done
md="${md%$'\n'}"

# ---- post a comment, or print ----
if [ -n "$target_kind" ]; then
  [ -n "$target_num" ] || die "--$target_kind needs a number"
  printf '%s\n' "$md" | gh "$target_kind" comment "$target_num" --body-file - \
    || die "failed to comment on $target_kind #$target_num"
  printf 'ghshot: commented on %s #%s\n' "$target_kind" "$target_num" >&2
  exit 0
fi

case "$mode" in
  raw)  printf '%s\n' "$first_url" ;;
  json) esc="$(printf '%s' "$md" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')"
        esc="${esc%\\n}"
        printf '{"url":"%s","markdown":"%s","backend":"release"}\n' "$first_url" "$esc" ;;
  *)    printf '%s\n' "$md" ;;
esac
