<!-- Thanks for contributing to ghshot! -->

## Summary

<!-- What does this PR change, and why? -->

## Component(s) touched

- [ ] CLI skill (`skills/ghshot/`)
- [ ] Bridge (`bridge/`)
- [ ] Extension (`extension/`)
- [ ] Docs / scaffolding
- [ ] Tests / CI

## Checklist

- [ ] Stays within the **low-dependency invariant** (bash 3.2 + coreutils + `gh` for the
      CLI; python3 stdlib for the bridge; plain JS for the extension; no build step).
- [ ] CLI stdout stays pipe-safe (URLs/markdown only; logs to stderr).
- [ ] Updated `README.md` / `SKILL.md` if behavior changed.
- [ ] Added/updated a **hermetic** bats test (no real network) for CLI changes.
- [ ] Ran `shellcheck`, `shfmt -d -i 2 -ci`, `python3 -m py_compile bridge/ghshot-bridge`,
      and `bats tests/` locally.

## Related issues

<!-- e.g. Closes #123 -->
