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

- **True access control.** Uploads go through your existing, authenticated github.com
  browser session to the `user-attachments` endpoint; the asset inherits the repository's
  ACL — only people who can see the repo can view the image. **No cookies are extracted
  and no GitHub credential is stored on disk.** The only local secret is the bridge token
  (`~/.config/ghshot/bridge-token`, chmod 0600). That token authorizes the bridge to upload
  through your browser session — anyone who holds it can upload to any repo you can write to
  while Chrome is open, so treat it as a real credential.
- **Never upload secrets** anyway. The CLI refuses sensitive-looking filenames and non-image
  files by default (a best-effort, filename-based guard — it does **not** inspect file
  contents, and the bridge does not re-vet what the CLI sends); `--force` bypasses it.

## Bridge hardening

The bridge (`bridge/ghshot-bridge`) is designed to be safe-by-default:

- binds **127.0.0.1 by default**; it can be bound to another address with `--host`
  (`GHSHOT_BRIDGE_HOST`) to reach it from another machine. When you do, it is reachable by
  anything that can route to that address, so security reduces to the bearer token + the
  origin/host guards — only bind a **trusted private network**, never `0.0.0.0` on a public
  one, and prefer an encrypted transport (plain `http://` sends the token in the clear),
- requires the `X-Ghshot-Token` header on every endpoint except `GET /healthz`,
- rejects any request whose `Origin` is an `http(s)://` website (so a malicious web page
  in your browser cannot drive uploads), allowing only absent or `chrome-extension://`
  origins,
- validates the `Host` header (IP literals, `localhost`, or the configured bind host only)
  to blunt DNS-rebinding, and ignores chunked `Transfer-Encoding`.

If you find a way to bypass any of these guards, please report it privately.
