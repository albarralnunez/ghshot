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
- [ ] Ran `make lint test` locally (shellcheck, shfmt, py_compile, `node --check`, bats
      and the node scraper tests).

## Related issues

<!-- e.g. Closes #123 -->
