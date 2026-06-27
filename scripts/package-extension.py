#!/usr/bin/env python3
"""Package extension/ into a Chrome Web Store .zip (stdlib only).

Usage: python3 scripts/package-extension.py <output.zip>

The zip has manifest.json at its root (Web Store requirement). Source maps,
dotfiles, and the icon generator are excluded.
"""

import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EXT = os.path.join(ROOT, "extension")

EXCLUDE_NAMES = {".DS_Store"}
EXCLUDE_EXT = {".map"}


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: package-extension.py <output.zip>")
    out = sys.argv[1]
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    if not os.path.isfile(os.path.join(EXT, "manifest.json")):
        sys.exit("extension/manifest.json not found")

    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for dirpath, dirnames, filenames in os.walk(EXT):
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
            for name in sorted(filenames):
                if name in EXCLUDE_NAMES or os.path.splitext(name)[1] in EXCLUDE_EXT:
                    continue
                if name.startswith("."):
                    continue
                full = os.path.join(dirpath, name)
                arc = os.path.relpath(full, EXT)
                z.write(full, arc)
                count += 1
    print("packaged %d files -> %s" % (count, out))


if __name__ == "__main__":
    main()
