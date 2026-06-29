# ghshot-bridge

A tiny local HTTP bridge that lets the `ghshot` CLI upload images through your
**existing github.com browser session** via the ghshot Chrome extension — so
attachments render **inline** and stay **access-controlled**, even on private
repos. No cookies are extracted and no secret is stored.

```
CLI (curl) ──HTTP──▶ ghshot-bridge ◀──HTTP long-poll── Chrome extension ──fetch──▶ github.com
                   (127.0.0.1 by default)             (your logged-in session)
```

The bridge never talks to GitHub itself. It just hands an image to the
extension and waits for the resulting `github.com/user-attachments/...` URL.

## Requirements

- Python 3 (standard library only — nothing to `pip install`)

## Run it

```sh
./ghshot-bridge
```

It binds `127.0.0.1` only and prints, to **stderr**, the Bridge URL and the
auth token to paste into the extension's options page:

```
[ghshot-bridge] v0.1.0 listening on http://127.0.0.1:41330
[ghshot-bridge] In the extension options set:
                  Bridge URL: http://127.0.0.1:41330
                  Token:      a1b2c3...
```

Stop it with `Ctrl-C` (clean shutdown).

> The file is a self-contained executable. If your checkout lost the exec bit:
> `chmod +x ghshot-bridge` (or run it as `python3 ghshot-bridge`).

## Configuration

| What        | Source (in precedence order)                                                            | Default                          |
|-------------|------------------------------------------------------------------------------------------|----------------------------------|
| Port        | `--port` ▸ `$GHSHOT_BRIDGE_PORT`                                                          | `41330`                          |
| Auth token  | `$GHSHOT_BRIDGE_TOKEN` ▸ token file (`--token-file`)                                      | `~/.config/ghshot/bridge-token`  |

If no token is supplied, the bridge **auto-creates** one (32 random hex chars)
at the token-file path with `chmod 0600`. The CLI reads the same file, so they
agree automatically on the same machine.

### CLI flags

```
--port PORT            TCP port to bind on 127.0.0.1
--token-file PATH      Path to the auth token file
--print-token          Print the resolved token and exit
--help                 Show usage
```

`./ghshot-bridge --print-token` is handy for copying the token into the
extension without scrolling the logs.

## Security model

- **Loopback by default.** The listener binds `127.0.0.1`. It can be bound
  elsewhere with `--host`/`GHSHOT_BRIDGE_HOST` to reach it from another machine;
  in that mode it is reachable by anything that can route to the address, so only
  bind a trusted private network (never `0.0.0.0` on a public one) and prefer an
  encrypted transport — plain `http://` sends the token and image in the clear.
- **Host guard.** Requests whose `Host` is a DNS name other than the configured
  bind host are rejected (IP literals and `localhost` allowed), blunting DNS
  rebinding. Chunked `Transfer-Encoding` is not accepted.
- **Token auth.** Every endpoint except `GET /healthz` requires the
  `X-Ghshot-Token` request header to equal the token.
- **Origin guard.** Any request carrying an `Origin` header that starts with
  `http://` or `https://` (i.e. a real website) is rejected with `403`. Only
  requests with no `Origin` (curl) or a `chrome-extension://` origin (the
  extension) are allowed. This stops a malicious web page from driving uploads.

## HTTP contract

All non-`/healthz` requests require header `X-Ghshot-Token: <token>`.

| Method & path        | Caller    | Behaviour                                                                                                                                                                                                 |
|----------------------|-----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `GET /healthz`       | CLI       | No auth. `200` `{"ok":true,"version":"0.1.0"}`. Used to detect the bridge.                                                                                                                                 |
| `POST /v1/upload`    | CLI       | `multipart/form-data` with `repo=owner/name` and `file=<image>`. Optional `?format=text`. Blocks up to 120 s. **Success:** `200` — `text/plain` URL when `?format=text`, else JSON `{"url":"..."}`.       |
| `GET /v1/poll`       | extension | Long-poll up to 25 s. `200` `{"id","repo","blob","filename"}` when a job is pending (`blob` is `/v1/blob/<id>`), else `204`.                                                                                |
| `GET /v1/blob/<id>`  | extension | Raw image bytes with a guessed `Content-Type`.                                                                                                                                                             |
| `POST /v1/result`    | extension | JSON `{"id","url"}` (success) or `{"id","error"}` (failure). Returns `200` `{"ok":true}`.                                                                                                                  |

### `/v1/upload` error responses

| Status | When                                                          | Body                                                                                      |
|--------|--------------------------------------------------------------|-------------------------------------------------------------------------------------------|
| `504`  | No extension polled/claimed the job within 30 s              | `{"error":"extension not connected — install the ghshot extension and keep Chrome open"}` |
| `504`  | Claimed, but no result before the 120 s deadline             | `{"error":"timed out waiting for the extension to finish the upload ..."}`                 |
| `502`  | Extension reported a failure                                 | `{"error":"<message from the extension>"}`                                                 |
| `400`  | Missing/empty `repo`/`file`, or unparseable multipart body   | `{"error":"..."}`                                                                          |
| `401`  | Missing/invalid `X-Ghshot-Token`                             | `{"error":"invalid token"}`                                                                |
| `403`  | Request `Origin` is an `http(s)://` website                  | `{"error":"forbidden origin"}`                                                             |

## Implementation notes

- **Standard library only.** `http.server.ThreadingHTTPServer` plus
  `threading`, `secrets`, `json`, `mimetypes`, `urllib`, and `email`.
- The legacy **`cgi`** module is intentionally **not** used (it was removed in
  Python 3.13). Multipart bodies are parsed with `email.parser.BytesParser`.
- The job store is an in-memory dict guarded by a single `threading.Condition`.
  Job ids are 16 hex chars. Jobs are removed as soon as the blocking
  `/v1/upload` returns, so nothing persists to disk.
- `SIGINT`/`SIGTERM` trigger a clean `server.shutdown()`.

## Quick manual test

```sh
# terminal 1
./ghshot-bridge --port 41330 --token-file /tmp/tok

# terminal 2 — pretend to be the CLI (blocks until the "extension" responds)
TOKEN=$(./ghshot-bridge --token-file /tmp/tok --print-token)
curl -fsS -H "X-Ghshot-Token: $TOKEN" \
  -F repo=octocat/hello -F file=@shot.png \
  "http://127.0.0.1:41330/v1/upload?format=text" &

# terminal 3 — pretend to be the extension
TOKEN=$(./ghshot-bridge --token-file /tmp/tok --print-token)
JOB=$(curl -fsS -H "X-Ghshot-Token: $TOKEN" http://127.0.0.1:41330/v1/poll)
ID=$(printf '%s' "$JOB" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')
curl -fsS -H "X-Ghshot-Token: $TOKEN" \
  -d "{\"id\":\"$ID\",\"url\":\"https://github.com/user-attachments/assets/demo\"}" \
  http://127.0.0.1:41330/v1/result
# terminal 2 now prints the URL
```
