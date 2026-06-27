# Contributing to ghshot

Thanks for helping out! `ghshot` deliberately stays tiny and auditable. Please read the
**low-dependency invariant** before opening a PR — it is the core design constraint and
PRs that violate it will be asked to change.

## The low-dependency invariant

Each component is restricted to a specific, minimal toolchain. Do not add new runtime
dependencies, package managers, or build steps.

| Component                 | Allowed dependencies                                              |
| ------------------------- | ---------------------------------------------------------------- |
| `skills/ghshot/ghshot.sh` | **bash 3.2** + coreutils + `gh` + `curl`. (`aws` only for the s3 backend.) |
| `bridge/ghshot-bridge`    | **python3 standard library only** — no pip, no venv, no removed `cgi`. |
| `extension/`              | **plain JS, MV3** — no npm, no bundler, no build step.            |
| transport                 | `curl` and HTTP long-poll only — no native messaging, no websockets. |

If your change needs something outside these lists, open an issue first to discuss.

## Project layout

```
skills/ghshot/   the CLI skill (ghshot.sh + SKILL.md)
bridge/          the loopback HTTP bridge (single python3 executable)
extension/       the MV3 Chrome extension
tests/           bats tests + hermetic stubs (no network)
.github/         CI, issue/PR templates, dependabot
```

Paths are **disjoint by component** — keep changes scoped to one area when you can.

## Development & checks

Run the same checks CI runs before pushing:

```bash
# shell
shellcheck skills/ghshot/ghshot.sh tests/stubs/gh tests/stubs/aws
shfmt -d -i 2 -ci skills/ghshot/ghshot.sh        # -d = diff only; drop -d to format

# python bridge
python3 -m py_compile bridge/ghshot-bridge

# tests (hermetic, no network)
bats tests/
```

All tests must stay **hermetic** — no real network, no real `gh`/`aws`. Use the stubs in
`tests/stubs/`.

## Commit & PR guidelines

- Keep stdout of the CLI **pipe-safe**: only URLs/markdown on stdout, all logs to stderr.
- Update the relevant `README.md` / `SKILL.md` when you change behavior.
- Add or update a bats test for any CLI behavior change.
- Use clear, conventional-ish commit subjects (e.g. `feat(bridge): …`, `fix(cli): …`).
- One logical change per PR.

## Code of Conduct

This project follows the [Contributor Covenant](./CODE_OF_CONDUCT.md). By participating,
you agree to uphold it.
