# ghshot

[![CI](https://github.com/albarralnunez/ghshot/actions/workflows/ci.yml/badge.svg)](https://github.com/albarralnunez/ghshot/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

Upload images (screenshots, diagrams) to GitHub PRs, issues, and comments from the
terminal — and get markdown-ready URLs back. GitHub has **no API** for attaching images
and `gh` can't do it ([cli/cli#4745](https://github.com/cli/cli/discussions/4745)).
`ghshot` fills the gap.

It ships as an agent **skill** (a small bash script) plus a tiny local **bridge** and a
**Chrome extension**. Together they upload through your *existing* github.com browser
session, producing a `user-attachments` URL that renders **inline** and is
**access-controlled to the repo** — works on **private** repos, with **no cookie
extraction and no stored secret**.

## How it works

```
ghshot.sh ──HTTP──▶ local bridge (127.0.0.1) ◀──long-poll── Chrome extension ──fetch(your session)──▶ github.com
```

The extension uses the session already in your browser to call GitHub's `user-attachments`
endpoint, so the asset is visible only to people who can see the repo. The script never
touches your cookie; the only local secret is the loopback bridge token.

## Install

### 1. The skill

```bash
npx skills add albarralnunez/ghshot
```

Your agent (Claude Code, Codex, Cursor, …) then knows to use it whenever you ask to
attach a screenshot to a PR. To run it directly, invoke the script by its **full path**
inside the skill directory:

```bash
/path/to/ghshot/skills/ghshot/ghshot.sh shot.png
```

### 2. The bridge

A single python3-stdlib executable. No pip, no venv.

```bash
bridge/ghshot-bridge            # binds 127.0.0.1:41330, prints its URL + token hint
bridge/ghshot-bridge --print-token   # show the token to paste into the extension
```

It auto-creates a token at `~/.config/ghshot/bridge-token` (chmod 0600) unless
`GHSHOT_BRIDGE_TOKEN` is set. Override the port with `GHSHOT_BRIDGE_PORT` (default 41330).

### 3. The Chrome extension

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
ghshot.sh shot.png                      # → inline markdown for the current repo
ghshot.sh --pr 42 shot.png              # upload + comment on PR #42
ghshot.sh --issue 10 bug.png            # upload + comment on issue #10
ghshot.sh --raw shot.png                # raw URL only
ghshot.sh --json shot.png               # {"url","markdown","visibility"}

# stdout is pipe-safe (URL/markdown only); progress goes to stderr
ghshot.sh shot.png | gh pr comment 42 --body-file -
```

The target repo is resolved from `GHSHOT_REPO`, else `gh repo view --json nameWithOwner`
in the current directory. `gh` is only used for that and for `--pr`/`--issue` comments;
the upload itself needs only `curl` + the bridge + the extension.

## Troubleshooting

- **`bridge not reachable`** → start `bridge/ghshot-bridge` and keep it running. Check it:
  `curl -fsS http://127.0.0.1:41330/healthz`.
- **`no bridge token found`** → set `GHSHOT_BRIDGE_TOKEN` or start the bridge to create the
  token file, then paste the token into the extension Options.
- **`upload failed` / `not signed in to github.com`** → sign in to github.com in the same
  Chrome profile the extension runs in, confirm the extension is loaded, then retry.
- **`gh not authenticated`** → run `gh auth login`.

## Managing / deleting uploads

Assets live under `github.com/user-attachments/assets/<uuid>` and are tied to the repo's
ACL. To remove one, delete the comment/PR body that references it; orphaned attachments are
not publicly listable.

## Security model

- **True access control.** The asset is visible only to accounts that can see the repo.
- **No secret leaves the browser.** Your github.com session is never extracted; the only
  thing on disk is the local bridge token (`~/.config/ghshot/bridge-token`, chmod 0600),
  which only authorizes the loopback bridge.
- **Never upload secrets anyway.** The skill refuses sensitive-looking filenames and
  non-images by default; `--force` bypasses the guard only when you are sure.

## Uninstall

```bash
npx skills remove albarralnunez/ghshot     # remove the skill
# stop the bridge (Ctrl-C) and rm -f ~/.config/ghshot/bridge-token
# chrome://extensions → Remove "ghshot"
```

## Credits

Inspired by [vipulgupta2048/gitshot](https://github.com/vipulgupta2048/gitshot); this is an
independent implementation that uploads through your own browser session via the bridge +
extension.

## License

[MIT](./LICENSE)
