---
name: ghshot
description: Upload an image (screenshot, diagram) to a GitHub PR, issue, or comment and get a markdown-ready URL. GitHub has no API for image upload and `gh` can't do it. ghshot uploads through your OWN logged-in github.com browser session via a tiny local bridge + a Chrome extension (no cookie extraction, no stored secret), producing a github.com/user-attachments URL that renders inline and is access-controlled to people who can see the repo — works on PRIVATE repos. Use when asked to attach/embed a screenshot, post a before/after image, or add a picture to a PR/issue/comment.
license: MIT
argument-hint: "<image-path> [--pr N | --issue N]"
allowed-tools:
  - Bash(gh:*)
  - Bash(bash:*)
metadata:
  author: albarralnunez
  version: 0.2.0
---

# ghshot — upload images to GitHub

GitHub has no API to attach images to PRs/issues/comments ([cli#4745](https://github.com/cli/cli/discussions/4745)). `ghshot.sh` (shipped next to this file) uploads through your **existing** logged-in github.com browser session and prints markdown-ready URLs that render **inline** and are **access-controlled to the repo** (works on private repos). No cookie is extracted and no secret is stored on disk.

```
ghshot.sh --HTTP--> local bridge (127.0.0.1) <--long-poll-- Chrome extension --fetch(your session)--> github.com
```

## Invoking the script

Run the script **by its full path in this skill's directory** — never a bare `bash ghshot.sh`, because your working directory is usually the user's project (so `gh repo view` resolves the right repo), not the skill directory.

```bash
# SKILL_DIR = the directory that contains this SKILL.md
"$SKILL_DIR/ghshot.sh" shot.png                 # → ![shot](https://github.com/user-attachments/assets/<uuid>)
"$SKILL_DIR/ghshot.sh" --pr 42 shot.png         # upload + comment on PR #42 (--issue N for issues)
"$SKILL_DIR/ghshot.sh" --pr 42 before.png after.png   # multiple images, one comment
"$SKILL_DIR/ghshot.sh" --raw shot.png           # raw URL only (for embedding in your own text)
"$SKILL_DIR/ghshot.sh" --json shot.png          # {"url","markdown","visibility"} — for agents
```

stdout is pipe-safe (only the URL/markdown); progress goes to stderr. You can pipe it:

```bash
"$SKILL_DIR/ghshot.sh" shot.png | gh pr comment 42 --body-file -
```

## One-time setup (required)

The upload rides your browser session, so two pieces must be running:

1. **Start the bridge** (python3 stdlib only, binds `127.0.0.1`):

   ```bash
   bridge/ghshot-bridge            # prints its URL + the token file location to stderr
   bridge/ghshot-bridge --print-token   # just print the auth token
   ```

   On first run it writes a 32-hex-char token to `~/.config/ghshot/bridge-token` (chmod 0600).
   Port defaults to `41330` (override with `--port` or `GHSHOT_BRIDGE_PORT`).

2. **Install the Chrome extension** (MV3, no build step): open `chrome://extensions`, enable
   *Developer mode*, *Load unpacked*, pick the `extension/` directory. Open the extension's
   **Options** and set the **Bridge URL** (default `http://127.0.0.1:41330`) and the **Token**
   (from `--print-token`); click *Test connection*.

3. **Stay signed in to github.com** in that Chrome profile and keep Chrome open. That's the
   session the upload rides on.

## How the script talks to the bridge

- Bridge URL: `GHSHOT_BRIDGE_URL`, else `http://127.0.0.1:$GHSHOT_BRIDGE_PORT` (default port `41330`).
- Token: `GHSHOT_BRIDGE_TOKEN`, else the contents of `~/.config/ghshot/bridge-token`.
- Repo to attach to: `GHSHOT_REPO`, else `gh repo view --json nameWithOwner -q .nameWithOwner`
  resolved from the **current working directory** (run the script from the user's project).

`gh` is only needed to resolve the repo (when `GHSHOT_REPO` is unset) and to post `--pr`/`--issue`
comments. The upload itself needs only `curl` + the bridge + the extension.

## Troubleshooting

- `bridge not reachable` → start `bridge/ghshot-bridge` and keep it running.
- `no bridge token found` → set `GHSHOT_BRIDGE_TOKEN` or start the bridge to create the token file.
- `upload failed` / `not signed in` → open Chrome, sign in to github.com, confirm the extension is
  loaded and its Options point at the right Bridge URL/token (*Test connection*).
- `gh not authenticated` → `gh auth login`.

## Security

- The asset is **access-controlled to people who can see the repo** (a real ACL, not obscurity).
- **Never upload secrets** anyway. The content guards refuse obviously sensitive filenames and
  non-images; `--force` / `GHSHOT_FORCE=1` bypasses them — only when you are sure.
- No github.com cookie is extracted and no GitHub credential is stored: the only local secret is
  the loopback bridge token at `~/.config/ghshot/bridge-token`.
