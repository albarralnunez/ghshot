# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.1] - 2026-06-27

### Fixed

- **Extension: robust github.com tab selection.** The upload (which runs inside a
  github.com tab) failed with `Frame with ID 0 is showing error page` when the chosen tab
  was discarded/suspended or an error page. It now skips discarded/unloaded tabs, tries
  every open github.com tab, and falls back to opening a fresh background tab (navigating
  and verifying it loaded) before injecting — with clearer errors.
- **Bridge: silence benign connection resets.** A client dropping a keep-alive socket
  (`ConnectionResetError` / `BrokenPipeError`) no longer logs a traceback.

## [0.3.0] - 2026-06-27

### Fixed

- **Extension uploads now work on private repos / with third-party cookies blocked.**
  The upload previously ran a cross-site `fetch` from the service worker; Chrome strips
  github.com's `SameSite` session cookies from that request when third-party cookies are
  blocked (increasingly the default), so GitHub served a logged-out page and the extension
  reported "not signed in". The upload now runs **inside a github.com tab** via
  `chrome.scripting.executeScript`, where requests are first-party and always carry the
  user's session. Adds the `scripting` + `tabs` permissions; reuses an existing github.com
  tab when present, otherwise opens (and closes) a background one.
- **Updated the GitHub HTML scraping** to current markup: `repository_id` from the
  `octolytics-dimension-repository_id` meta and the upload token from the page's
  `"uploadToken"` payload (with `/issues/new` + `csrf-token` fallbacks). The old
  `data-upload-*` selectors no longer exist and matched nothing, which also produced the
  misleading "not signed in" error. The sign-in check now reads the `user-login` meta.

## [0.2.1] - 2026-06-27

### Changed

- Documentation and the extension's host permissions are now network-agnostic: the host
  permissions cover loopback and the common private ranges (`10.*`, `192.168.*`, `100.*`)
  instead of naming any particular VPN/overlay.

## [0.2.0] - 2026-06-27

### Added

- **Remote bridge bind** — `ghshot-bridge --host <addr>` (or `GHSHOT_BRIDGE_HOST`)
  binds a non-loopback address so a browser on another machine can reach the bridge. Still
  token-gated and origin-guarded; default stays `127.0.0.1`.
- **Multiple bridges in the extension** — the Options page now manages a *list* of
  bridges (URL + token each), and the service worker polls them all concurrently. Use it
  to drive a local bridge and a remote bridge from one browser. Legacy single-bridge
  settings are migrated automatically.

## [0.1.1] - 2026-06-27

### Fixed

- Bridge CORS: the extension's **Options → Test connection** (and any preflighted request
  from an extension *page*, which—unlike the service worker—does not get the host-permission
  CORS exemption) failed with `TypeError: Failed to fetch`. The bridge now answers
  `OPTIONS` preflights (204) and echoes `Access-Control-Allow-Origin` for
  `chrome-extension://` origins, with `Vary: Origin` and `Access-Control-Allow-Headers:
  X-Ghshot-Token, Content-Type`. Website origins are still rejected; non-browser callers
  (no Origin) get no CORS headers. Uploads were unaffected (they run in the CORS-exempt
  service worker).

### Added

- Chrome Web Store packaging: generated extension icons (16/48/128), a privacy policy
  (`PRIVACY.md`), a store listing + screenshot placeholder (`store/`), a stdlib asset
  generator (`scripts/gen-assets.py`), and `make zip` / `make assets` / `make lint` /
  `make test` targets.

## [0.1.0] - 2026-06-27

### Added

- **CLI skill** (`skills/ghshot/ghshot.sh`): bash script that uploads images to GitHub
  PRs/issues/comments and prints markdown-ready URLs. **True-private + inline** uploads via
  the user's existing github.com browser session (through the bridge + extension) — the
  asset is access-controlled to people who can see the repo; works on private repos.
  - Flags: `--pr`, `--issue`, `--raw`, `--json`, `--force`, `--version`, `--help`.
  - Refuse-by-default guards for sensitive-looking filenames, non-images, and oversize files.
- **Bridge** (`bridge/ghshot-bridge`): single python3-stdlib loopback HTTP service that
  brokers upload jobs between the CLI and the extension. Binds 127.0.0.1, token auth,
  origin guard, long-poll job queue.
- **Chrome extension** (`extension/`): MV3 extension that long-polls the bridge and
  performs the `user-attachments` upload from the user's authenticated session — no cookie
  extraction, no stored secret.
- **OSS scaffolding**: README, SECURITY, CONTRIBUTING, CODE_OF_CONDUCT, this changelog,
  CI (shellcheck, shfmt, py_compile, bats on Ubuntu + macOS), issue/PR templates,
  dependabot, and hermetic bats tests with a `gh` stub.

[Unreleased]: https://github.com/albarralnunez/ghshot/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/albarralnunez/ghshot/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/albarralnunez/ghshot/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/albarralnunez/ghshot/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/albarralnunez/ghshot/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/albarralnunez/ghshot/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/albarralnunez/ghshot/releases/tag/v0.1.0
