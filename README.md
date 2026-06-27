# ghshot

[![CI](https://github.com/albarralnunez/ghshot/actions/workflows/ci.yml/badge.svg)](https://github.com/albarralnunez/ghshot/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

Upload images (screenshots, diagrams) to GitHub PRs, issues, and comments from the
terminal — and get markdown-ready URLs back. GitHub has **no API** for attaching images
and `gh` can't do it ([cli/cli#4745](https://github.com/cli/cli/discussions/4745)).
`ghshot` fills the gap.

It ships as an agent **skill** (a single dependency-free bash script) plus two optional
pieces — a tiny local **bridge** and a **Chrome extension** — that together unlock
**true-private, inline** uploads through your *existing* github.com browser session, with
**no cookie extraction and no stored secret**.

## Backends

`ghshot` has two hosting backends. Same script, same markdown output — they differ only
in where the bytes live and what guarantees you get.

| Backend       | Private?                         | Inline render?                 | Extra deps                       | How it works |
| ------------- | -------------------------------- | ------------------------------ | -------------------------------- | ------------ |
| `attachments` | **Yes — true repo ACL**          | **Yes**                        | bridge (python3 stdlib) + Chrome extension | Uploads via your authenticated github.com session to the `user-attachments` endpoint. The asset is access-controlled to people who can see the repo. |
| `release`     | **Yes** by default (then a link) | Only when `--public`           | none (just `gh`)                 | Bytes go to a release asset on a dedicated `<you>/ghshot-images` repo. Private assets render as a **link**; `--public` renders inline. |

**Backend auto-selection** (when you don't pass `--backend` / set `GHSHOT_BACKEND`):

1. If the **bridge is healthy** → `attachments` (the marquee path: true private + inline).
2. Else → `release` (private link).

`attachments` is the recommended backend: it is the only one that gives a **real
access-controlled inline image** on a **private** repo, and it never stores a secret —
it reuses the session already in your browser.

## Install

### 1. The skill (required)

```bash
npx skills add albarralnunez/ghshot
```

Your agent (Claude Code, Codex, Cursor, …) then knows to use it whenever you ask to
attach a screenshot to a PR. To run it directly, invoke the script by its **full path**
inside the skill directory:

```bash
/path/to/ghshot/skills/ghshot/ghshot.sh shot.png
```

### 2. The bridge (for the `attachments` backend)

The bridge is a single python3-stdlib executable. No pip, no venv.

```bash
bridge/ghshot-bridge            # binds 127.0.0.1:41330, prints its URL + token hint
bridge/ghshot-bridge --print-token   # show the token to paste into the extension
```

It auto-creates a token at `~/.config/ghshot/bridge-token` (chmod 0600) unless
`GHSHOT_BRIDGE_TOKEN` is set. Override the port with `GHSHOT_BRIDGE_PORT` (default 41330).

### 3. The Chrome extension (for the `attachments` backend)

1. Open `chrome://extensions`, enable **Developer mode**.
2. **Load unpacked** → select the `extension/` directory.
3. Open the extension's **Options**, set:
   - **Bridge URL**: `http://127.0.0.1:41330` (default)
   - **Token**: the value from `bridge/ghshot-bridge --print-token`
4. Click **Test connection** — it should report `ok` and the version.

Keep Chrome open and signed in to github.com. The extension long-polls the bridge and
performs uploads from your session. **No cookies are exported and no password is stored.**

## Quickstart

```bash
# auto-selects attachments if the bridge is up, else release
ghshot.sh shot.png                      # → markdown for the current repo

ghshot.sh --pr 42 shot.png              # upload + comment on PR #42
ghshot.sh --issue 10 bug.png            # upload + comment on issue #10
ghshot.sh --raw shot.png                # raw URL only
ghshot.sh --json shot.png               # {"url","markdown","backend","visibility"}

ghshot.sh --backend attachments shot.png   # force the private+inline path
ghshot.sh --backend release --public shot.png   # public release asset, inline

# stdout is pipe-safe (URL/markdown only); progress goes to stderr
ghshot.sh shot.png | gh pr comment 42 --body-file -
```

The target repo for `attachments` is resolved from `GHSHOT_REPO`, else
`gh repo view --json nameWithOwner` in the current directory.

## Troubleshooting

- **`gh not authenticated`** → run `gh auth login`.
- **`extension not connected` (504)** → install/enable the Chrome extension and keep
  Chrome open. Confirm the bridge is running: `curl -fsS http://127.0.0.1:41330/healthz`.
- **`not signed in to github.com in this browser` (502)** → sign in to github.com in the
  same Chrome profile the extension runs in, then retry.
- **Bridge token mismatch** → re-copy the token from `bridge/ghshot-bridge --print-token`
  into the extension Options, or export `GHSHOT_BRIDGE_TOKEN` for both.
- **Private release image won't render** → that's expected; GitHub won't proxy private
  release assets. Use the `attachments` backend (inline + private) or `--public`.

## Managing / deleting uploads

- **attachments**: assets live under `github.com/user-attachments/assets/<uuid>`. They are
  tied to the repo's ACL. Remove the comment/PR body that references them; orphaned
  attachments are not publicly listable.
- **release**: assets are files on the `_ghshot` release of `<you>/ghshot-images`.
  Delete one with `gh release delete-asset _ghshot <name> --repo <you>/ghshot-images`,
  or delete the whole repo to wipe everything.

## Security model

- **attachments** — *true access control*. The asset is visible only to accounts that can
  see the repo. Nothing is stored on disk except a local bridge token; your github.com
  session never leaves the browser.
- **public release** (`--public`) — *security by obscurity*. The URL is unguessable but
  **not** access-controlled; anyone with the link can view it.
- **Never upload secrets.** The skill refuses sensitive-looking filenames and non-images
  by default; `--force` bypasses the guard only when you are sure.

## Uninstall

```bash
npx skills remove albarralnunez/ghshot     # remove the skill
# stop the bridge (Ctrl-C) and rm -f ~/.config/ghshot/bridge-token
# chrome://extensions → Remove "ghshot"
# optionally: gh repo delete <you>/ghshot-images
```

## Credits

This is a clean-room reimplementation inspired by the GitHub-release backend of
[vipulgupta2048/gitshot](https://github.com/vipulgupta2048/gitshot), packaged as a skill
and extended with the bridge + extension `attachments` path.

## License

[MIT](./LICENSE)
