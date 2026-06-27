# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/albarralnunez/ghshot/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/albarralnunez/ghshot/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/albarralnunez/ghshot/releases/tag/v0.1.0
