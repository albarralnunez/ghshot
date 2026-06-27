---
name: ghshot
description: Upload an image (screenshot, diagram) to a GitHub PR, issue, or comment and get a markdown-ready URL. GitHub has no API for image upload and `gh` can't do it, so this ships a tiny dependency-free bash script that stores images as release assets on a public <you>/ghshot-images repo (only needs an authenticated `gh` — no node, no npm, no session cookie). Use when asked to attach/embed a screenshot, post a before/after image, or add a picture to a PR/issue/comment.
license: MIT
argument-hint: "<image-path> [--pr N | --issue N]"
allowed-tools:
  - Bash(gh:*)
  - Bash(bash:*)
metadata:
  author: albarralnunez
  version: 0.1.0
---

# ghshot — upload images to GitHub

GitHub has no API to attach images to PRs/issues/comments ([cli#4745](https://github.com/cli/cli/discussions/4745)). `ghshot.sh` (shipped next to this file) does it with only an authenticated `gh` CLI — no node, no npm, no session cookie. It stores images as release assets on a dedicated **public** `<you>/ghshot-images` repo (auto-created on first use) and prints markdown-ready URLs.

## Use it

Run the script that sits in this skill's directory:

```bash
bash ghshot.sh shot.png                 # → ![shot](https://github.com/<you>/ghshot-images/releases/download/_ghshot/shot-ab12cd34.png)
bash ghshot.sh --pr 42 shot.png         # upload + comment on PR #42 (--issue N for issues)
bash ghshot.sh --pr 42 before.png after.png   # multiple images, one comment
bash ghshot.sh --raw shot.png           # raw URL only (for embedding in your own text)
bash ghshot.sh --json shot.png          # {"url":"...","markdown":"...","backend":"release"} — for agents
```

stdout is pipe-safe (only the URL/markdown); progress goes to stderr. So you can also pipe:

```bash
bash ghshot.sh shot.png | gh pr comment 42 --body-file -
```

## Requirements

- `gh` authenticated (`gh auth login`). That's it.
- First run auto-creates `<you>/ghshot-images` (public) with a holding release `_ghshot`.

## Warning

`ghshot-images` is **public** — anyone with the URL can view uploads. Do **not** upload sensitive images (credentials, internal dashboards, private data).
