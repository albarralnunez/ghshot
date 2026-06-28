# ghshot — dev & packaging targets. Low-dep: bash, python3, shellcheck, shfmt, bats.

EXT_VERSION := $(shell sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' extension/manifest.json | head -1)
DIST := dist
ZIP := $(DIST)/ghshot-extension-$(EXT_VERSION).zip

.PHONY: help zip assets lint test clean

help:
	@echo "ghshot make targets:"
	@echo "  make zip      package extension/ -> $(ZIP) (upload to the Web Store)"
	@echo "  make assets   regenerate icons + store screenshot placeholder"
	@echo "  make lint     shellcheck + shfmt + py_compile + node --check"
	@echo "  make test     run the bats suite"
	@echo "  make clean    remove $(DIST)/"

zip:
	@python3 scripts/package-extension.py "$(ZIP)"

assets:
	python3 scripts/gen-assets.py

lint:
	shellcheck skills/ghshot/ghshot.sh tests/stubs/gh tests/stubs/curl
	shfmt -d -i 2 -ci skills/ghshot/ghshot.sh
	python3 -m py_compile bridge/ghshot-bridge
	node --check extension/background.js
	node --check extension/options.js

test:
	bats tests/

clean:
	rm -rf "$(DIST)"
