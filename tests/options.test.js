// Static checks on extension/options.html (the page that holds bridge tokens).
// Run: node --test tests/options.test.js  (node >= 18, no dependencies)

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const html = fs.readFileSync(path.join(__dirname, "..", "extension", "options.html"), "utf8");
const js = fs.readFileSync(path.join(__dirname, "..", "extension", "options.js"), "utf8");

test("the token field is masked by default", () => {
  const inputs = html.match(/<input\b[^>]*\bclass="b-token"[^>]*>/g) || [];
  assert.equal(inputs.length, 1);
  assert.match(inputs[0], /\btype="password"/);
});

test("options.js never sets the token field to text except while revealing", () => {
  const sets = js.match(/tokenInput\.type\s*=\s*[^;]+;/g) || [];
  assert.deepEqual(sets, ['tokenInput.type = on ? "text" : "password";']);
  for (const ev of ["pointerup", "pointerleave", "pointercancel", "blur"]) {
    assert.ok(js.includes(`"${ev}"`), `re-masks on ${ev}`);
  }
});
