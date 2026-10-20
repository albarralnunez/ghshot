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

Get the extension one of two ways:

- **From the latest release (no clone needed)** — download and unzip:

  ```bash
  curl -fsSL -o ghshot-extension.zip \
    https://github.com/albarralnunez/ghshot/releases/latest/download/ghshot-extension.zip
  unzip ghshot-extension.zip -d ghshot-extension
  ```

  ([latest release page](https://github.com/albarralnunez/ghshot/releases/latest) ·
  [direct download](https://github.com/albarralnunez/ghshot/releases/latest/download/ghshot-extension.zip) —
  both always point at the newest version.)

- **From a clone** — just use the `extension/` directory in this repo.

Then load it:

1. Open `chrome://extensions`, enable **Developer mode**.
2. **Load unpacked** → select the unzipped `ghshot-extension/` folder (or the repo's
   `extension/` directory).
3. Open the extension's **Options**, set:
   - **Bridge URL**: `http://127.0.0.1:41330` (default)
   - **Token**: the value from `bridge/ghshot-bridge --print-token`. The field is masked;
     hold **Show** to read it back, and it masks again on release
4. Click **Save**, then **Test connection** — it should report `ok` and the bridge's
   version. Three things that catch people out:
   - **A newly loaded unpacked extension starts with empty storage.** Removing the extension
     wipes its storage, and loading it from a different folder gives it a different
     extension id (Chrome derives it from the folder path), so in both cases bridges and
     tokens must be entered again. The reload button on the card keeps them.
   - **The CLI only talks to the bridge on its own machine** (`GHSHOT_BRIDGE_URL`). Each
     machine that runs the CLI needs its own bridge, and the extension needs an entry for
     each one, with *that* machine's token.
   - **Test connection does not check the token.** It hits the unauthenticated `/healthz`,
     so it passes with a wrong or missing token. A wrong token shows up as jobs that are
     never claimed (`extension not connected`).

Keep Chrome open and signed in to github.com. The extension long-polls the bridge and
performs uploads from your session. **No cookies are exported and no password is stored.**

## Remote bridge & multiple bridges

The CLI/bridge and your browser don't have to be on the same machine. To upload from a
project on **machine A** while the browser/session lives on **machine B**, bind the bridge
to a private address both can reach and point the extension at it:

```bash
# on machine A (where ghshot runs):
ghshot-bridge --host 10.0.0.5            # an address machine B can reach; or GHSHOT_BRIDGE_HOST=...
export GHSHOT_BRIDGE_URL=http://10.0.0.5:41330   # so the CLI hits the same address
```

Then in the extension **Options** on machine B, add a bridge with URL
`http://10.0.0.5:41330` and that bridge's token. The bridge stays **token-gated and
origin-guarded**, but is now reachable on the chosen interface — only bind an address on a
**trusted private network** (never `0.0.0.0` on a public one).

The extension supports **multiple bridges** at once — add as many URL+token pairs as you
like (e.g. a local `127.0.0.1` bridge and a remote one); it polls them all and handles
whichever has a job. (The extension reaches a bridge at any address via the bridge's own
CORS headers, so a remote bridge needs no extra extension permission — just a reachable
URL and its token.)

### Import / export the bridge list

Instead of pasting URLs and tokens by hand, each bridge host can print its own entry, and
the extension's Options can **Import** it:

```bash
# on each bridge host — the output contains the token, so redirect it, never print it
umask 077   # the file is a secret: keep it private to you
ghshot-bridge --print-bridge-entry --host 10.0.0.5 > entry.json
# behind NAT or DNS, give the URL the browser should use instead
ghshot-bridge --print-bridge-entry --url http://build-box.example:41330 > entry.json
# several hosts → one file
jq -s '{bridges: map(.bridges[])}' entry-a.json entry-b.json > bridges.json
```

The format is `{"bridges": [{"url": …, "token": …}]}`. `--print-bridge-entry` refuses a
loopback or wildcard `--host` (the default is `127.0.0.1`) unless `--url` is given, because
such an entry is useless to a browser on another machine.

In Options, **Import…** merges the file into the saved bridges **by URL** (case-insensitive):
a URL already listed gets the file's token, a new URL is added, and nothing is removed.
Unsaved edits on the page are discarded. A file with any invalid entry (not
`http(s)://host[:port]`, no token, a duplicate URL) is rejected whole. **Export** writes the
saved bridges that have a token in the same format. Both files carry tokens in plain text — keep them out of
repos and delete them after the import.

## Quickstart

```bash
ghshot.sh shot.png                      # → inline markdown for the current repo
ghshot.sh --pr 42 shot.png              # upload + comment on PR #42
ghshot.sh --pr shot.png                 # no number → the current branch's PR
ghshot.sh --pick shot.png               # interactively pick repo + PR (needs fzf)
ghshot.sh --repo owner/name --pr 42 shot.png   # target a repo from any directory
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
- **`extension not connected`** with the extension loaded → open `chrome://extensions`,
  click the ghshot card's **service worker** link, set the console level to **Verbose**
  (the extension logs with `console.debug`), and look for `[ghshot] loop start: <url>`
  per bridge. No loop line means no bridge has both a URL and a token saved; repeated
  `poll … returned HTTP 401` means a wrong token. If the card says the extension is
  disabled, turn **Developer mode** back on: Chrome disables unpacked extensions without it.
  `lsof -nP -iTCP:41330 -sTCP:ESTABLISHED` should list a Chrome connection per bridge.
- **`could not find upload tokens on the repo page (GitHub HTML changed)`** → GitHub moved
  the upload token again. The error says which value is missing and lists related key
  names on the page (never values); open an issue with that line.
- **`upload failed` / `not signed in to github.com`** → sign in to github.com in the same
  Chrome profile the extension runs in, confirm the extension is loaded, then retry.
- **`gh not authenticated`** → run `gh auth login`.

## Managing / deleting uploads

Assets live under `github.com/user-attachments/assets/<uuid>` and are tied to the repo's
ACL. To remove one, delete the comment/PR body that references it; orphaned attachments are
not publicly listable.

## Security model

- **True access control.** The asset is visible only to accounts that can see the repo.
- **No GitHub credential leaves the browser.** Your github.com session is never extracted.
  The only secret on disk is the local bridge token (`~/.config/ghshot/bridge-token`, chmod
  0600); it authorizes the bridge to upload through your session, so anyone who holds it can
  upload to repos you can write to while Chrome is open — treat it as a real credential.
- **Never upload secrets anyway.** The skill refuses sensitive-looking filenames and
  non-images by default — a best-effort, filename-based guard (it does not inspect file
  contents, and the bridge does not re-vet uploads); `--force` bypasses it.

## Uninstall

```bash
npx skills remove albarralnunez/ghshot     # remove the skill
# stop the bridge (Ctrl-C) and rm -f ~/.config/ghshot/bridge-token
# chrome://extensions → Remove "ghshot"
```

## Publishing the extension

The extension is store-ready. To package it:

```bash
make zip          # → dist/ghshot-extension-<version>.zip
```

Upload that zip in the [Chrome Web Store dashboard](https://chrome.google.com/webstore/devconsole)
(one-time $5 developer registration). Listing copy and permission justifications are in
[`store/listing.md`](./store/listing.md); replace the placeholder
[`store/screenshot-1.png`](./store/) with real captures (see [`store/README.md`](./store/README.md)).
Icons live in `extension/icons/` and are regenerated with `make assets`.

Privacy policy: [`PRIVACY.md`](./PRIVACY.md) (also the policy URL for the store form).

Tip: for personal/small-team use you don't need the store at all — **Load unpacked** the
`extension/` directory from `chrome://extensions`. The store is only for wider, searchable
distribution (expect a permissions-justification review because of the github.com host
access). The same MV3 build also works on Firefox (AMO).

## Credits

Inspired by [vipulgupta2048/gitshot](https://github.com/vipulgupta2048/gitshot); this is an
independent implementation that uploads through your own browser session via the bridge +
extension.

## License

[MIT](./LICENSE)
