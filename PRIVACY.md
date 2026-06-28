# ghshot — Privacy Policy

_Last updated: 2026-06-27_

ghshot is a developer tool for uploading images to GitHub. This policy covers the
**ghshot Chrome extension** and the local **bridge** it talks to.

## Short version

ghshot has **no servers**, collects **no analytics**, and sends your data to **no third
party**. Images you choose to upload go directly from your browser to **github.com** using
the session you are already signed in with. Nothing about your activity is transmitted to
the developer.

## What the extension accesses

- **Your active github.com session.** When *you* trigger an upload, the extension makes
  requests to `github.com` with your existing cookies (`credentials: "include"`) to call
  GitHub's `user-attachments` endpoint. The extension **never reads, copies, stores, or
  transmits your cookies or password** — it only rides the session your browser already
  has, the same way the GitHub website's own upload button does.
- **Image bytes you select.** The bytes of the image you ask to upload are fetched from the
  local bridge and POSTed to GitHub. They are not retained by the extension.
- **A local bridge URL and token** that you enter in the extension's Options. These are
  stored with `chrome.storage.local` on your own machine so the extension can talk to the
  bridge at `http://127.0.0.1`. They never leave your device except as the loopback request
  to the bridge.

## What the extension does NOT do

- No analytics, telemetry, tracking, or fingerprinting.
- No remote/developer servers — there is no backend to receive your data.
- No selling or sharing of data with anyone.
- No reading of github.com pages other than the repository page needed to perform an upload
  you initiated.
- No access to any site other than `github.com` and `127.0.0.1` (see `host_permissions` in
  `manifest.json`).

## The local bridge

`bridge/ghshot-bridge` runs only on your machine, bound to `127.0.0.1` (loopback). It
brokers an upload job from the command-line tool to the extension. It stores a single
random auth token at `~/.config/ghshot/bridge-token` (file mode `0600`). It makes no
outbound network connections.

## Data sharing & GitHub

The only external party that receives data is **GitHub**, and only the image you chose to
upload, under your own account/session. GitHub's handling of that data is governed by the
[GitHub Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).

## Permissions justification

- `host_permissions: https://github.com/*` — to perform the upload in your authenticated
  session.
- `host_permissions: http://127.0.0.1/*` — to receive jobs from the local bridge.
- `storage` — to remember the bridge URL and token you configure.
- `alarms` — to keep the background service worker alive so it can receive upload jobs.

## Changes

Material changes will update the date above and be noted in `CHANGELOG.md`.

## Contact

Questions or reports: open an issue at
<https://github.com/albarralnunez/ghshot/issues> (do not include secrets), or use the
private channel described in [SECURITY.md](./SECURITY.md).
