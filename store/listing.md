# Chrome Web Store listing — copy & metadata

Paste these into the Web Store developer dashboard when publishing `extension/`.

## Name

ghshot — inline image upload for GitHub

## Summary (≤132 chars)

Attach screenshots to GitHub PRs, issues & comments from the terminal — inline, even on private repos, via your own session.

## Category

Developer Tools

## Description

ghshot uploads images to GitHub through your **existing, logged-in github.com session** —
no cookie extraction, no password, no third-party server. The resulting
`github.com/user-attachments` URL renders **inline** and is **access-controlled to the
repository**, so it works on **private** repos.

This extension is the browser half of the open-source ghshot tool. It pairs with a tiny
local "bridge" and a command-line script: you run `ghshot shot.png` (or your AI agent
does), the bridge hands the job to this extension, and the extension performs the upload in
your authenticated GitHub tab. Nothing about your activity is sent to the developer — there
is no backend.

Open source (MIT): https://github.com/albarralnunez/ghshot

Setup (one time):
1. Install the ghshot CLI/skill and run the local bridge (`ghshot-bridge`).
2. Load this extension and, in its Options, set the Bridge URL and token.
3. Stay signed in to github.com. Done.

## Permissions justification (for the review form)

- **github.com host access** — performs the image upload in your authenticated session
  (the same `user-attachments` endpoint the GitHub website uses). Required for the core
  function.
- **127.0.0.1 host access** — receives upload jobs from the local bridge over loopback.
- **storage** — saves the bridge URL and auth token you enter in Options.
- **alarms** — keeps the MV3 service worker alive to receive jobs.

No remote code, no analytics, no data sale. Privacy policy:
https://github.com/albarralnunez/ghshot/blob/main/PRIVACY.md

## Assets

- Icon: `extension/icons/icon128.png`
- Screenshots: 1280×800 or 640×400 PNG/JPEG. See `store/README.md` for what to capture.
  `store/screenshot-1.png` is a placeholder — replace it before publishing.

## Distribution recommendation

- **Unlisted** for personal / small-team use (install by link, lighter scrutiny).
- **Public** once real screenshots + the privacy policy URL are in place; expect a
  permissions-justification round-trip because of the github.com host permission.
