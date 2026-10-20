// ghshot page scrapers — pure functions that find the repository id and the
// upload token in a github.com page's HTML.
//
// Injected into the github.com tab (chrome.scripting.executeScript files:[…])
// right before pageUpload runs in the same isolated world, where they are read
// from globalThis.ghshotScrape. Also loaded by tests/scrape.test.js under node.
//
// GitHub moves these values between server-rendered attributes and the React
// apps' embedded JSON (raw, backslash-escaped or HTML-entity encoded), so every
// known shape is tried. Never return or log a token value anywhere but the
// caller: the diagnostic lists key names only.

(function () {
  "use strict";

  const m1 = (s, re) => {
    const m = s.match(re);
    return m ? m[1] : null;
  };

  // Collapse every quote encoding seen in GitHub's HTML to a plain ".
  const unquote = (s) =>
    s
      .replace(/&quot;|&#0*34;|&#x0*22;/gi, '"')
      .replace(/\\u0022/gi, '"')
      .replace(/\\"/g, '"');

  // Every embedded JSON blob on the page: <script type="application/json" …>,
  // which carries the React apps' state (data-target="react-app.embeddedData").
  // Parsing it survives escaping changes that a regex over the HTML does not.
  function embeddedJson(s) {
    const out = [];
    const re = /<script\b[^>]*\btype="application\/json"[^>]*>([\s\S]*?)<\/script>/gi;
    let m;
    while ((m = re.exec(s))) {
      try {
        out.push(JSON.parse(m[1]));
      } catch (e) {
        /* not JSON — skip */
      }
    }
    return out;
  }

  // Depth-first search for the first value `pick` accepts.
  function walk(value, pick, depth) {
    if (depth > 64 || value === null || typeof value !== "object") return null;
    const hit = Array.isArray(value) ? null : pick(value);
    if (hit) return hit;
    for (const v of Array.isArray(value) ? value : Object.values(value)) {
      const t = walk(v, pick, depth + 1);
      if (t) return t;
    }
    return null;
  }

  // Strict on purpose: a loose match could pick up another repo's id, and the
  // upload would then be scoped to that repo. The JSON form only accepts an
  // object naming exactly this owner/repo.
  const findRepoId = (s, owner, repo) =>
    m1(s, /name="octolytics-dimension-repository_id"\s+content="(\d+)"/) ||
    m1(s, /name="hovercard-subject-tag"\s+content="repository:(\d+)"/) ||
    m1(s, /\bdata-upload-repository-id="(\d+)"/) ||
    m1(s, /name="repository_id"[^>]*\bvalue="(\d+)"/) ||
    (owner && repo ? repoIdFromJson(s, owner, repo) : null);

  function repoIdFromJson(s, owner, repo) {
    const lc = (x) => String(x).toLowerCase();
    const pick = (o) =>
      Number.isSafeInteger(o.id) &&
      o.id > 0 &&
      typeof o.name === "string" &&
      typeof o.ownerLogin === "string" &&
      lc(o.name) === lc(repo) &&
      lc(o.ownerLogin) === lc(owner)
        ? String(o.id)
        : null;
    for (const data of embeddedJson(s)) {
      const id = walk(data, pick, 0);
      if (id) return id;
    }
    return null;
  }

  const TOKEN_KEY = /^(uploadToken|upload_?policy_?authenticity_?token)$/i;
  // Authenticity tokens are base64/base64url; anything else is not one.
  const TOKEN_VALUE = /^[A-Za-z0-9+/=_-]{8,512}$/;

  function fromEmbeddedJson(s) {
    const pick = (o) => {
      for (const k of Object.keys(o)) {
        const v = o[k];
        if (TOKEN_KEY.test(k) && typeof v === "string" && TOKEN_VALUE.test(v)) return v;
      }
      return null;
    };
    for (const data of embeddedJson(s)) {
      const t = walk(data, pick, 0);
      if (t) return t;
    }
    return null;
  }

  // Returns { token, source } — source names the shape that matched (no value).
  // Structured and server-rendered shapes go first: the regexes over unquoted
  // text could also match a key/value pair quoted in rendered repo content.
  function findUploadToken(s) {
    const flat = unquote(s);
    const tries = [
      ["embedded-json", () => fromEmbeddedJson(s)],
      ["data-upload-policy-authenticity-token", () => m1(s, /\bdata-upload-policy-authenticity-token="([^"]+)"/)],
      ["uploadToken", () => m1(flat, /"uploadToken"\s*:\s*"([^"\\]+)"/)],
      ["upload_policy_authenticity_token", () => m1(flat, /"upload_?policy_?authenticity_?token"\s*:\s*"([^"\\]+)"/i)],
      ["csrf-token meta", () => m1(s, /<meta name="csrf-token" content="([^"]+)"/)],
    ];
    for (const [source, f] of tries) {
      const token = f();
      if (token && TOKEN_VALUE.test(token)) return { token, source };
    }
    return { token: null, source: null };
  }

  // The comment form's token on issues/new. A last resort: it may not be
  // accepted by /upload/policies/assets, so callers report when it was used.
  const findFormToken = (s) => {
    const t = m1(s, /name="authenticity_token"[^>]*\bvalue="([^"]+)"/);
    return t && TOKEN_VALUE.test(t) ? t : null;
  };

  // Key names only (never values), to say what GitHub serves when a lookup fails.
  const relatedKeys = (s) =>
    Array.from(
      new Set(
        (unquote(s).match(/"[A-Za-z_]*(?:upload|authenticity|repository_?id)[A-Za-z_]*"\s*:/gi) || []).map((k) =>
          k.replace(/\s*:$/, "")
        )
      )
    ).slice(0, 20);

  const api = { unquote, findRepoId, findUploadToken, findFormToken, relatedKeys };
  globalThis.ghshotScrape = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})();
