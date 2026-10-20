"use strict";

const DEFAULT_BRIDGE_URL = "http://127.0.0.1:41330";

const bridgesEl = document.getElementById("bridges");
const tpl = document.getElementById("bridge-tpl");
const addButton = document.getElementById("add");
const saveButton = document.getElementById("save");
const statusEl = document.getElementById("status");
const importButton = document.getElementById("import");
const importFile = document.getElementById("import-file");
const exportButton = document.getElementById("export");

function setStatus(message, kind) {
  statusEl.textContent = message;
  statusEl.className = kind || "";
}

function normalizeUrl(url) {
  return (url || "").trim().replace(/\/+$/, "");
}

// Add one bridge row (optionally prefilled).
function addRow(url, token) {
  const node = tpl.content.firstElementChild.cloneNode(true);
  const urlInput = node.querySelector(".b-url");
  const tokenInput = node.querySelector(".b-token");
  const rowStatus = node.querySelector(".bridge-status");
  urlInput.value = url || "";
  tokenInput.value = token || "";

  // The token stays masked: the page is often on a screen someone else can
  // see (a KVM, a screen share). "Show" reveals it only while held down.
  const showButton = node.querySelector(".b-show");
  const reveal = (on) => {
    tokenInput.type = on ? "text" : "password";
    showButton.textContent = on ? "Hide" : "Show";
  };
  showButton.addEventListener("pointerdown", () => reveal(true));
  for (const ev of ["pointerup", "pointerleave", "pointercancel", "blur"]) {
    showButton.addEventListener(ev, () => reveal(false));
  }

  node.querySelector(".b-remove").addEventListener("click", () => {
    node.remove();
  });

  node.querySelector(".b-test").addEventListener("click", async () => {
    const u = normalizeUrl(urlInput.value) || DEFAULT_BRIDGE_URL;
    rowStatus.textContent = "Testing…";
    rowStatus.className = "bridge-status";
    try {
      const resp = await fetch(u + "/healthz");
      if (!resp.ok) {
        rowStatus.textContent = `HTTP ${resp.status}`;
        rowStatus.className = "bridge-status err";
        return;
      }
      const data = await resp.json();
      if (data && data.ok) {
        rowStatus.textContent = `OK — v${data.version || "?"}`;
        rowStatus.className = "bridge-status ok";
      } else {
        rowStatus.textContent = "Unexpected response";
        rowStatus.className = "bridge-status err";
      }
    } catch (err) {
      rowStatus.textContent = `Unreachable: ${String(err)}`;
      rowStatus.className = "bridge-status err";
    }
  });

  bridgesEl.appendChild(node);
}

async function storedBridges() {
  const stored = await chrome.storage.local.get(["bridges", "bridgeUrl", "token"]);
  let list = Array.isArray(stored.bridges) ? stored.bridges : [];
  if (!list.length && (stored.bridgeUrl || stored.token)) {
    list = [{ url: stored.bridgeUrl || DEFAULT_BRIDGE_URL, token: stored.token || "" }];
  }
  return list;
}

async function load() {
  bridgesEl.replaceChildren();
  let list = await storedBridges();
  if (!list.length) list = [{ url: DEFAULT_BRIDGE_URL, token: "" }];
  for (const b of list) addRow(b.url, b.token);
}

async function save() {
  const rows = [...bridgesEl.querySelectorAll(".bridge")];
  const seen = new Set();
  const bridges = [];
  for (const row of rows) {
    const url = normalizeUrl(row.querySelector(".b-url").value);
    const token = row.querySelector(".b-token").value.trim();
    if (!url) continue;
    if (seen.has(url)) {
      setStatus(`Duplicate bridge URL: ${url}`, "err");
      return;
    }
    if (!token) {
      // The service worker skips a bridge with no token, so it would never be
      // polled and its jobs would fail as "extension not connected".
      setStatus(`Bridge ${url} has no token — paste it from that machine's ~/.config/ghshot/bridge-token.`, "err");
      return;
    }
    seen.add(url);
    bridges.push({ url, token });
  }
  // Persist the list; drop the legacy single-bridge keys.
  await chrome.storage.local.set({ bridges });
  await chrome.storage.local.remove(["bridgeUrl", "token"]);
  setStatus(`Saved ${bridges.length} bridge(s).`, "ok");
}

// Import merges into the SAVED list (see bridges.js), never replaces it.
async function importBridges(file) {
  let incoming;
  try {
    incoming = ghshotBridges.parseImport(await file.text());
  } catch (err) {
    setStatus(`Import failed: ${err.message}`, "err");
    return;
  }
  try {
    const { bridges, added, updated } = ghshotBridges.mergeBridges(await storedBridges(), incoming);
    await chrome.storage.local.set({ bridges });
    await chrome.storage.local.remove(["bridgeUrl", "token"]);
    await load();
    setStatus(
      `Imported ${incoming.length} bridge(s): ${added} added, ${updated} token(s) updated, ` +
        `${incoming.length - added - updated} unchanged. Delete the file now.`,
      "ok"
    );
  } catch (err) {
    setStatus(`Import failed: ${String((err && err.message) || err)}`, "err");
  }
}

async function exportBridges() {
  try {
    const { text, count, skipped } = ghshotBridges.exportText(await storedBridges());
    if (!count) {
      setStatus("Nothing to export: no saved bridge has a token.", "err");
      return;
    }
    const url = URL.createObjectURL(new Blob([text], { type: "application/json" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = "ghshot-bridges.json";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    setStatus(
      `Exported ${count} bridge(s)${skipped ? ` (${skipped} without a token skipped)` : ""}. ` +
        "The file contains their tokens — keep it private.",
      "ok"
    );
  } catch (err) {
    setStatus(`Export failed: ${String((err && err.message) || err)}`, "err");
  }
}

addButton.addEventListener("click", () => addRow("", ""));
saveButton.addEventListener("click", save);
importButton.addEventListener("click", () => importFile.click());
importFile.addEventListener("change", () => {
  const file = importFile.files && importFile.files[0];
  importFile.value = "";
  if (file) importBridges(file);
});
exportButton.addEventListener("click", exportBridges);

load();
