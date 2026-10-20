// Unit tests for extension/scrape.js (the github.com page scrapers).
// Run: node --test tests/scrape.test.js  (node >= 18, no dependencies)

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const scrape = require("../extension/scrape.js");

const TOKEN = "AbC123+/xyz_-=TokEn0123456789";
const OWNER = "octo";
const REPO = "hello-world";
const REPO_ID = "424242";
const META = `<meta name="octolytics-dimension-repository_id" content="${REPO_ID}" />`;

const embedded = (obj) =>
  `<script type="application/json" data-target="react-app.embeddedData">${JSON.stringify(obj)}</script>`;

// Every shape GitHub has served the upload token in. Each must yield TOKEN exactly.
const TOKEN_FIXTURES = {
  "embedded JSON script": embedded({ payload: { repo: { id: 1 }, uploadToken: TOKEN } }),
  "raw JSON in inline script": `<script>window.x = {"uploadToken":"${TOKEN}","a":1};</script>`,
  "backslash-escaped JSON": `<script>var s = "{\\"uploadToken\\":\\"${TOKEN}\\"}";</script>`,
  "\\u0022-escaped JSON": `<script>var s = "{\\u0022uploadToken\\u0022:\\u0022${TOKEN}\\u0022}";</script>`,
  "&quot;-encoded attribute": `<div data-props="{&quot;uploadToken&quot;:&quot;${TOKEN}&quot;}"></div>`,
  "&#34;-encoded attribute": `<div data-props="{&#34;uploadToken&#34;:&#34;${TOKEN}&#34;}"></div>`,
  "&#x22;-encoded attribute": `<div data-props="{&#x22;uploadToken&#x22;:&#x22;${TOKEN}&#x22;}"></div>`,
  "snake_case key, raw": `<script>x = {"upload_policy_authenticity_token": "${TOKEN}"}</script>`,
  "snake_case key, embedded JSON": embedded({ a: [{ b: { upload_policy_authenticity_token: TOKEN } }] }),
  "attribute form": `<file-attachment data-upload-policy-authenticity-token="${TOKEN}"></file-attachment>`,
  "csrf meta (legacy)": `<meta name="csrf-token" content="${TOKEN}" />`,
};

for (const [name, html] of Object.entries(TOKEN_FIXTURES)) {
  test(`upload token: ${name}`, () => {
    const r = scrape.findUploadToken(META + html);
    assert.equal(r.token, TOKEN);
    assert.ok(r.source, "a source is named");
  });
}

test("upload token: saved logged-out repo page", () => {
  const html = fs.readFileSync(path.join(__dirname, "fixtures", "logged-out-repo.html"), "utf8");
  assert.deepEqual(scrape.findUploadToken(html), {
    token: "FixtureLoggedOutToken0123456789+/_-=",
    source: "embedded-json",
  });
  assert.equal(scrape.findRepoId(html, "albarralnunez", "ghshot"), "1282387928");
});

test("upload token: the embedded JSON wins over a stale attribute", () => {
  const html = `<div data-upload-policy-authenticity-token="stale-attribute-token"></div>` + embedded({ uploadToken: TOKEN });
  assert.deepEqual(scrape.findUploadToken(html), { token: TOKEN, source: "embedded-json" });
});

test("upload token: a server-rendered attribute wins over a pair quoted in page text", () => {
  const html =
    `<article><code>{&quot;uploadToken&quot;:&quot;PlantedInReadme0000&quot;}</code></article>` +
    `<file-attachment data-upload-policy-authenticity-token="${TOKEN}"></file-attachment>`;
  assert.deepEqual(scrape.findUploadToken(html), { token: TOKEN, source: "data-upload-policy-authenticity-token" });
});

test("upload token: a null or junk value is not a token", () => {
  assert.equal(scrape.findUploadToken(embedded({ uploadToken: null })).token, null);
  assert.equal(scrape.findUploadToken(embedded({ uploadToken: "has spaces in it" })).token, null);
  assert.equal(scrape.findUploadToken(embedded({ uploadToken: 12345678 })).token, null);
  assert.equal(scrape.findUploadToken("<html><body>nothing</body></html>").token, null);
});

test("upload token: malformed JSON script is skipped, not thrown", () => {
  const html = `<script type="application/json">{not json</script>` + embedded({ uploadToken: TOKEN });
  assert.equal(scrape.findUploadToken(html).token, TOKEN);
});

test("issues/new form token", () => {
  const html = `<form><input type="hidden" name="authenticity_token" value="${TOKEN}" autocomplete="off"></form>`;
  assert.equal(scrape.findFormToken(html), TOKEN);
});

test("repo id: each server-rendered form", () => {
  const forms = [
    `<meta name="octolytics-dimension-repository_id" content="${REPO_ID}" />`,
    `<meta name="hovercard-subject-tag" content="repository:${REPO_ID}" data-turbo-transient>`,
    `<file-attachment data-upload-repository-id="${REPO_ID}">`,
    `<input type="hidden" name="repository_id" id="x" value="${REPO_ID}">`,
  ];
  for (const html of forms) assert.equal(scrape.findRepoId(html, OWNER, REPO), REPO_ID, html);
});

test("repo id: embedded JSON only for this exact owner/repo", () => {
  const html = embedded({
    payload: {
      forks: [{ id: 1111, name: REPO, ownerLogin: "someone-else" }],
      other: { id: 2222, name: "other-repo", ownerLogin: OWNER },
      repo: { id: Number(REPO_ID), name: "Hello-World", ownerLogin: "Octo" },
    },
  });
  assert.equal(scrape.findRepoId(html, OWNER, REPO), REPO_ID);
  assert.equal(scrape.findRepoId(html, OWNER, "missing"), null);
  assert.equal(scrape.findRepoId(html), null, "no owner/repo, no JSON match");
});

test("repo id: loose numbers elsewhere are never taken", () => {
  const html = `<div data-repository-id="999"></div><script>{"repositoryId":999,"repository_id":"999"}</script>`;
  assert.equal(scrape.findRepoId(html, OWNER, REPO), null);
});

test("unquote: every quote encoding", () => {
  assert.equal(scrape.unquote(`&quot;a&#34;b&#x22;c&#X22;d\\u0022e\\"f&#034;`), `"a"b"c"d"e"f"`);
});

// The diagnostic ends up in the bridge log and the CLI's output: names only.
test("diagnostic lists key names and never a value", () => {
  const html =
    embedded({ uploadToken: TOKEN, repositoryId: 7 }) +
    `<div data-props="{&quot;upload_policy_authenticity_token&quot;:&quot;${TOKEN}&quot;}"></div>` +
    `<script>var s = "{\\"authenticityToken\\":\\"${TOKEN}\\"}";</script>` +
    `<input name="authenticity_token" value="${TOKEN}">`;
  const keys = scrape.relatedKeys(html);
  assert.ok(keys.includes('"uploadToken"'), keys.join(" "));
  assert.ok(keys.includes('"upload_policy_authenticity_token"'), keys.join(" "));
  const joined = keys.join(" ");
  assert.ok(!joined.includes(TOKEN), "token value leaked into the diagnostic");
  assert.ok(!joined.includes("TokEn"), "token fragment leaked into the diagnostic");
  for (const k of keys) assert.match(k, /^"[A-Za-z_]+"$/);
});
