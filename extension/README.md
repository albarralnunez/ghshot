# ghshot Chrome extension

This MV3 extension lets the ghshot CLI upload images to GitHub's
**user-attachments** storage through your **existing github.com browser
session**. The result is a `https://github.com/user-attachments/assets/<uuid>`
URL that:

- renders **inline** in issues, PRs, and comments, and
- is **access-controlled** to people who can see the repo — so it works on
  **private** repos.

No cookies are extracted and no token is stored: the upload rides your real,
already-authenticated github.com login (`fetch(..., { credentials: "include" })`).

## How it fits together

```
ghshot.sh (CLI)  --HTTP-->  ghshot-bridge (localhost)  <--long-poll--  this extension  --fetch-->  github.com
```

1. The CLI POSTs an image to the local bridge.
2. The bridge holds the request and queues a job.
3. This extension long-polls the bridge, fetches the image bytes, and uploads
   them to GitHub from your session.
4. The extension reports the final inline URL back to the bridge, which returns
   it to the CLI.

## Install (load unpacked)

1. Start the bridge (see the repo root README): `bridge/ghshot-bridge`.
   Note the token it prints, or run `bridge/ghshot-bridge --print-token`.
2. Open `chrome://extensions` in Chrome (or any Chromium-based browser).
3. Toggle **Developer mode** on (top right).
4. Click **Load unpacked** and select this `extension/` directory.
5. Open the extension's **Options** page (Details → Extension options, or the
   puzzle-piece menu → ghshot → Options).
6. Set:
   - **Bridge URL** — default `http://127.0.0.1:41330` (match
     `GHSHOT_BRIDGE_PORT` if you changed it).
   - **Token** — paste the bridge token.
7. Click **Save**, then **Test connection** — you should see the bridge version.
8. Make sure you are **signed in to github.com** in the same browser.

## Configuration

| Setting     | Default                  | Notes                                          |
| ----------- | ------------------------ | ---------------------------------------------- |
| Bridge URL  | `http://127.0.0.1:41330` | Where the local bridge listens.                |
| Token       | _(none)_                 | Must equal the bridge token. Uploads are idle until set. |

Both are stored in `chrome.storage.local`.

## Files

- `manifest.json` — MV3 manifest (permissions: `storage`, `alarms`; host
  permissions for github.com and localhost).
- `background.js` — service worker: the long-poll loop and the GitHub
  user-attachments upload flow.
- `options.html` / `options.js` — configuration UI and a health-check button.

## How the upload works (undocumented GitHub flow)

`uploadToGitHub(repo, blob, filename)` in `background.js`:

1. Fetches the authenticated repo HTML and scrapes `repository_id`, the upload
   policy URL, and the upload authenticity token. If the page looks logged-out
   it throws **"not signed in to github.com in this browser"**.
2. POSTs to the upload-policy endpoint to obtain S3 form fields and the final
   asset href.
3. POSTs the image bytes to the storage `upload_url` (a plain S3 form POST, no
   GitHub credentials).
4. PUTs to the asset-upload URL to finalize the asset on github.com.
5. Returns the `asset.href` inline URL.

> This GitHub endpoint is **undocumented** and reverse-engineered from the web
> UI. If uploads break, re-inspect a manual image paste on a repo page and
> adjust the regexes / field names centralized at the top of `background.js`.

## Troubleshooting

- **Options "Test connection" fails** — the bridge is not running, or the
  Bridge URL/port is wrong. Start `bridge/ghshot-bridge`.
- **Uploads fail with "not signed in to github.com in this browser"** — open
  https://github.com in this browser and log in, then retry.
- **Nothing happens / CLI times out with "extension not connected"** — the
  extension has no token configured, the token is wrong, or Chrome is closed.
  Open the Options page, re-check Bridge URL + Token, and keep Chrome running.
- **Inspect logs** — `chrome://extensions` → ghshot → **service worker**
  (Inspect views). Each upload step is logged via `console.debug`.

MV3 service workers are evicted when idle; the extension restarts its poll loop
from `onInstalled`, `onStartup`, and a 1-minute `chrome.alarms` keepalive.

## Security

- The extension only talks to your **local** bridge and to **github.com**.
- It never stores your GitHub credentials; it reuses your live browser session.
- The bridge token gates access so local processes can't drive uploads without
  it. Treat the token like a local secret.
- Never upload secrets: anyone who can see the repo can see the attachment.
