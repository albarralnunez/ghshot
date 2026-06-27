---
name: ghshot
description: Upload an image (screenshot, diagram) to a GitHub PR, issue, or comment and get a markdown-ready URL. GitHub has no API for image upload and `gh` can't do it. Two backends: attachments (TRUE private + inline via your own logged-in github.com browser session through a tiny local bridge + Chrome extension — no cookie extraction, no stored secret; works on PRIVATE repos) and release (dependency-free, needs only an authenticated `gh`). Use when asked to attach/embed a screenshot, post a before/after image, or add a picture to a PR/issue/comment.
license: MIT
argument-hint: "<image-path> [--pr N | --issue N] [--backend attachments|release]"
allowed-tools:
  - Bash(gh:*)
  - Bash(bash:*)
metadata:
  author: albarralnunez
  version: 0.1.0
---

# ghshot — upload images to GitHub

GitHub has no API to attach images to PRs/issues/comments ([cli#4745](https://github.com/cli/cli/discussions/4745)). `ghshot.sh` (shipped next to this file) solves it with two backends, then prints markdown-ready URLs.

## Invoking the script

Run the script **by its full path in this skill's directory** — never a bare `bash ghshot.sh`, because your working directory is usually the user's project (so `gh repo view` resolves the right repo), not the skill directory. Resolve the directory of this SKILL.md and call the script there:

```bash
# SKILL_DIR = the directory that contains this SKILL.md
"$SKILL_DIR/ghshot.sh" shot.png
```

Examples (replace `$SKILL_DIR` with the real absolute path of this skill's folder):

```bash
"$SKILL_DIR/ghshot.sh" shot.png                 # → ![shot](https://github.com/user-attachments/assets/<uuid>)  (attachments)
"$SKILL_DIR/ghshot.sh" --pr 42 shot.png         # upload + comment on PR #42 (--issue N for issues)
"$SKILL_DIR/ghshot.sh" --pr 42 before.png after.png   # multiple images, one comment
"$SKILL_DIR/ghshot.sh" --raw shot.png           # raw URL only (for embedding in your own text)
"$SKILL_DIR/ghshot.sh" --json shot.png          # {"url","markdown","backend","visibility"} — for agents
"$SKILL_DIR/ghshot.sh" --backend release shot.png   # force a specific backend
```

stdout is pipe-safe (only the URL/markdown); progress goes to stderr. You can pipe it:

```bash
"$SKILL_DIR/ghshot.sh" shot.png | gh pr comment 42 --body-file -
```

## Backends & visibility matrix

| backend       | private repos | renders inline | extra deps                      | URL access model                          |
|---------------|:-------------:|:--------------:|---------------------------------|-------------------------------------------|
| `attachments` | ✅ yes        | ✅ yes         | bridge + Chrome extension       | **TRUE ACL** — only people who can see the repo |
| `release`     | ✅ yes        | ❌ no (private)¹| only an authenticated `gh`      | security-by-obscurity (unguessable URL)   |

¹ A **private** GitHub release asset cannot render inline (GitHub won't proxy it), so it is emitted as a `[link]`. Use `--public` for an inline-rendering release repo, or prefer `attachments`.

**Auto-selection** (when neither `--backend` nor `GHSHOT_BACKEND` is set):

1. `attachments` if the local bridge is running (`GET /healthz` on the bridge succeeds), else
2. `release`.

`attachments` is the marquee backend: **true private + inline**, using the user's own
github.com session. No session cookie is extracted and no secret is stored on disk.

## The attachments backend: bridge + extension

The image flows:

```
ghshot.sh --HTTP--> local bridge (127.0.0.1) <--long-poll-- Chrome extension --fetch(session)--> github.com
```

The extension uploads through your **existing** logged-in github.com browser tab to the
undocumented `user-attachments` endpoint and returns a `github.com/user-attachments/assets/<uuid>`
URL that renders inline and is access-controlled to anyone who can see the repo.

### One-time setup

1. **Start the bridge** (python3 stdlib only, binds `127.0.0.1`):

   ```bash
   bridge/ghshot-bridge            # prints its URL + the token file location to stderr
   bridge/ghshot-bridge --print-token   # just print the auth token
   ```

   On first run it writes a 32-hex-char token to `~/.config/ghshot/bridge-token` (chmod 0600).
   Port defaults to `41330` (override with `--port` or `GHSHOT_BRIDGE_PORT`).

2. **Install the Chrome extension** (MV3, no build step): open `chrome://extensions`, enable
   *Developer mode*, *Load unpacked*, pick the `extension/` directory. Then open the extension's
   **Options** and set the **Bridge URL** (default `http://127.0.0.1:41330`) and the **Token**
   (paste the value from `~/.config/ghshot/bridge-token` or `--print-token`); click *Test connection*.

3. **Stay signed in to github.com** in that Chrome profile and keep Chrome open. That's the
   session the upload rides on.

### How the script talks to the bridge

- Bridge URL: `GHSHOT_BRIDGE_URL`, else `http://127.0.0.1:$GHSHOT_BRIDGE_PORT` (default port `41330`).
- Token: `GHSHOT_BRIDGE_TOKEN`, else the contents of `~/.config/ghshot/bridge-token`.
- Repo to attach to: `GHSHOT_REPO`, else `gh repo view --json nameWithOwner -q .nameWithOwner`
  resolved from the **current working directory** (run the script from the user's project).

## Requirements

- **attachments**: the bridge running + the extension installed and signed in to github.com.
  (`gh` is only used to resolve the repo when `GHSHOT_REPO` is unset.)
- **release**: `gh` authenticated (`gh auth login`). First run auto-creates `<you>/ghshot-images`
  (private by default) with a holding release `_ghshot`.

## Troubleshooting

- `bridge not reachable` → start `bridge/ghshot-bridge` and keep it running.
- `no bridge token found` → set `GHSHOT_BRIDGE_TOKEN` or start the bridge to create the token file.
- `attachments upload failed` / `not signed in` → open Chrome, sign in to github.com, confirm the
  extension is loaded and its Options point at the right Bridge URL/token (*Test connection*).
- `gh not authenticated` (release backend or `--pr/--issue`) → `gh auth login`.

## Security

- **Never upload secrets.** The content guards refuse obviously sensitive filenames and non-images;
  `--force` / `GHSHOT_FORCE=1` bypasses them — only when you are sure.
- A **public** `release` URL is **security-by-obscurity**: unguessable, but anyone with the
  link can view it.
- `attachments` is the only backend with a **true ACL**: the asset is access-controlled to people
  who can see the repo.
