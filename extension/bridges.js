// ghshot bridge-list helpers for the options page's Import/Export — pure
// functions, also loaded by tests/bridges.test.js under node.
//
// The file format is the storage format: {"bridges":[{"url":…,"token":…}]}
// (what `ghshot-bridge --print-bridge-entry` prints).

(function () {
  "use strict";

  // Same normalization as background.js getBridges(): trimmed, no trailing
  // slash. Entries without a URL are dropped.
  function normalizeEntry(b) {
    const url = String((b && b.url) || "")
      .trim()
      .replace(/\/+$/, "");
    const token = String((b && b.token) || "").trim();
    return { url, token };
  }

  // The canonical form of a bridge URL ("http(s)://host[:port]", lowercase,
  // as URL normalizes it), or null when it is anything more than that.
  function canonicalUrl(url) {
    if (/[?#@\\%\s]/.test(url)) return null;
    let u;
    try {
      u = new URL(url);
    } catch (e) {
      return null;
    }
    if (!/^https?:$/.test(u.protocol) || !u.hostname || u.pathname !== "/") return null;
    return `${u.protocol}//${u.host}`;
  }

  // Parse an import file. Throws an Error with a user-facing message (never
  // echoing a token) when the file is not usable.
  function parseImport(text) {
    let data;
    try {
      data = JSON.parse(text);
    } catch (e) {
      throw new Error("not a JSON file");
    }
    if (!data || typeof data !== "object" || !Array.isArray(data.bridges)) {
      throw new Error('expected {"bridges": [{"url": …, "token": …}]}');
    }
    const out = [];
    const seen = new Set();
    data.bridges.forEach((b, i) => {
      const e = normalizeEntry(b);
      const url = canonicalUrl(e.url);
      if (!url) throw new Error(`bridge ${i + 1}: url must be http(s)://host[:port]`);
      e.url = url;
      if (!e.token) throw new Error(`bridge ${i + 1} (${e.url}): no token`);
      if (seen.has(e.url)) throw new Error(`bridge ${i + 1}: duplicate url ${e.url}`);
      seen.add(e.url);
      out.push(e);
    });
    if (!out.length) throw new Error("the file lists no bridges");
    return out;
  }

  // Merge imported entries into the existing list by (canonical) url: an
  // imported url replaces that entry's token in place, a new url is appended,
  // and nothing already configured is ever dropped.
  function mergeBridges(existing, incoming) {
    const list = (existing || []).map(normalizeEntry).filter((b) => b.url);
    const key = (url) => canonicalUrl(url) || url;
    let added = 0;
    let updated = 0;
    for (const b of incoming) {
      const i = list.findIndex((x) => key(x.url) === key(b.url));
      if (i === -1) {
        list.push({ url: b.url, token: b.token });
        added++;
      } else if (list[i].token !== b.token) {
        list[i] = { url: b.url, token: b.token };
        updated++;
      }
    }
    return { bridges: list, added, updated };
  }

  // Only bridges with a url and a token are exportable (the import would
  // reject the rest); `skipped` counts what was left out.
  function exportText(bridges) {
    const all = (bridges || []).map(normalizeEntry).filter((b) => b.url);
    const list = all.filter((b) => b.token);
    return { text: JSON.stringify({ bridges: list }, null, 2) + "\n", count: list.length, skipped: all.length - list.length };
  }

  const api = { normalizeEntry, canonicalUrl, parseImport, mergeBridges, exportText };
  globalThis.ghshotBridges = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})();
