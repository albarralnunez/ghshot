# Security Policy

## Supported versions

`ghshot` is pre-1.0. Security fixes land on `main` and ship in the next release.

| Version | Supported |
| ------- | --------- |
| 0.1.x   | ✅        |

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use GitHub's **private vulnerability reporting** (Security → *Report a vulnerability*) on
this repository. If that is unavailable, email the maintainer at the address on their
GitHub profile. We aim to acknowledge within 7 days.

When reporting, include:

- affected component (`skills/ghshot/ghshot.sh`, `bridge/`, or `extension/`),
- a minimal reproduction,
- the impact you observed.

## Security model (what ghshot does and does not protect)

- **attachments backend** — the only backend with *true access control*. Uploads go
  through your existing, authenticated github.com browser session to the
  `user-attachments` endpoint; the asset inherits the repository's ACL. **No cookies are
  extracted and no GitHub credential is stored on disk.** The only local secret is the
  bridge token (`~/.config/ghshot/bridge-token`, chmod 0600), which only authorizes the
  loopback bridge.
- **s3 / public release backends** — *security by obscurity*. URLs are unguessable but
  **not** access-controlled; anyone with the link can view the image.
- **Never upload secrets.** The CLI refuses sensitive-looking filenames and non-image
  files by default; `--force` bypasses that guard.

## Bridge hardening

The bridge (`bridge/ghshot-bridge`) is designed to be safe-by-default:

- binds **127.0.0.1 only** (never a public interface),
- requires the `X-Ghshot-Token` header on every endpoint except `GET /healthz`,
- rejects any request whose `Origin` is an `http(s)://` website (so a malicious web page
  in your browser cannot drive uploads), allowing only absent or `chrome-extension://`
  origins.

If you find a way to bypass any of these guards, please report it privately.
