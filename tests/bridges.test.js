// Unit tests for extension/bridges.js (the options page's Import/Export).
// Run: node --test tests/bridges.test.js  (node >= 18, no dependencies)

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { parseImport, mergeBridges, exportText } = require("../extension/bridges.js");

const T1 = "token-one-AAAAAAAAAAAAAAAA";
const T2 = "token-two-BBBBBBBBBBBBBBBB";

test("parseImport: the --print-bridge-entry shape, normalized", () => {
  const got = parseImport(JSON.stringify({ bridges: [{ url: " http://100.69.42.73:41330/ ", token: ` ${T1}\n` }] }));
  assert.deepEqual(got, [{ url: "http://100.69.42.73:41330", token: T1 }]);
});

test("parseImport: rejects unusable files without echoing a token", () => {
  const cases = [
    ["not json", /not a JSON file/],
    [JSON.stringify([{ url: "http://a:1", token: T1 }]), /expected/],
    [JSON.stringify({ bridges: [] }), /no bridges/],
    [JSON.stringify({ bridges: [{ url: "ftp://a", token: T1 }] }), /url must be/],
    [JSON.stringify({ bridges: [{ url: "http://a:1/v1/poll", token: T1 }] }), /url must be/],
    [JSON.stringify({ bridges: [{ url: "http://:pw@a:1", token: T1 }] }), /url must be/],
    [JSON.stringify({ bridges: [{ url: "http://a?", token: T1 }] }), /url must be/],
    [JSON.stringify({ bridges: [{ url: "http://a#", token: T1 }] }), /url must be/],
    [JSON.stringify({ bridges: [{ url: "http://a:abc", token: T1 }] }), /url must be/],
    [JSON.stringify({ bridges: [{ url: "http://a:99999", token: T1 }] }), /url must be/],
    [JSON.stringify({ bridges: [{ url: "javascript:alert(1)", token: T1 }] }), /url must be/],
    [JSON.stringify({ bridges: [{ url: "http://a:1", token: "" }] }), /no token/],
    [JSON.stringify({ bridges: [{ url: "http://a:1", token: T1 }, { url: "HTTP://A:1/", token: T2 }] }), /duplicate/],
  ];
  for (const [text, re] of cases) {
    assert.throws(() => parseImport(text), (e) => {
      assert.match(e.message, re);
      assert.ok(!e.message.includes(T1) && !e.message.includes(T2), "token in error message");
      return true;
    });
  }
});

test("mergeBridges: merges by url and never drops an existing bridge", () => {
  const existing = [
    { url: "http://127.0.0.1:41330", token: "local" },
    { url: "http://100.69.42.73:41330/", token: "old" },
  ];
  const r = mergeBridges(existing, [
    { url: "http://100.69.42.73:41330", token: T1 },
    { url: "http://100.64.0.9:41330", token: T2 },
  ]);
  assert.deepEqual(r.bridges, [
    { url: "http://127.0.0.1:41330", token: "local" },
    { url: "http://100.69.42.73:41330", token: T1 },
    { url: "http://100.64.0.9:41330", token: T2 },
  ]);
  assert.equal(r.added, 1);
  assert.equal(r.updated, 1);
});

test("mergeBridges: the url match ignores case, so it updates instead of duplicating", () => {
  const r = mergeBridges([{ url: "http://Dan-Main:41330", token: "old" }], parseImport(JSON.stringify({ bridges: [{ url: "HTTP://dan-main:41330", token: T1 }] })));
  assert.deepEqual(r.bridges, [{ url: "http://dan-main:41330", token: T1 }]);
  assert.equal(r.updated, 1);
});

test("mergeBridges: re-importing the same file changes nothing", () => {
  const incoming = [{ url: "http://100.69.42.73:41330", token: T1 }];
  const once = mergeBridges([], incoming);
  const twice = mergeBridges(once.bridges, incoming);
  assert.deepEqual(twice.bridges, once.bridges);
  assert.equal(twice.added + twice.updated, 0);
});

test("exportText round-trips through parseImport", () => {
  const bridges = [
    { url: "http://127.0.0.1:41330", token: T1 },
    { url: "http://100.69.42.73:41330", token: T2 },
  ];
  const out = exportText(bridges);
  assert.equal(out.count, 2);
  assert.equal(out.skipped, 0);
  assert.deepEqual(parseImport(out.text), bridges);
});

test("exportText skips and counts bridges without a token", () => {
  const out = exportText([
    { url: "http://a:1", token: "" },
    { url: "http://b:1", token: T1 },
  ]);
  assert.equal(out.count, 1);
  assert.equal(out.skipped, 1);
  assert.deepEqual(JSON.parse(out.text), { bridges: [{ url: "http://b:1", token: T1 }] });
  assert.equal(exportText([{ url: "http://a:1", token: "" }]).count, 0);
});
