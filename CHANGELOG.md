# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-27

### Added

- **CLI skill** (`skills/ghshot/ghshot.sh`): dependency-free bash script that uploads
  images to GitHub PRs/issues/comments and prints markdown-ready URLs.
  - `attachments` backend — **true-private + inline** uploads via the user's existing
    github.com browser session, auto-selected when the bridge is healthy.
  - `release` backend — GitHub release assets on a dedicated `<you>/ghshot-images` repo,
    **private by default** (emitted as a link), `--public` for inline rendering.
  - Flags: `--pr`, `--issue`, `--backend`, `--public`, `--private`, `--raw`, `--json`,
    `--force`, `--yes`, `--version`, `--help`.
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

[Unreleased]: https://github.com/albarralnunez/ghshot/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/albarralnunez/ghshot/releases/tag/v0.1.0
