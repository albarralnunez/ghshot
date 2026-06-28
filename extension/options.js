"use strict";

const DEFAULT_BRIDGE_URL = "http://127.0.0.1:41330";

const bridgesEl = document.getElementById("bridges");
const tpl = document.getElementById("bridge-tpl");
const addButton = document.getElementById("add");
const saveButton = document.getElementById("save");
const statusEl = document.getElementById("status");

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

async function load() {
  const stored = await chrome.storage.local.get(["bridges", "bridgeUrl", "token"]);
  let list = Array.isArray(stored.bridges) ? stored.bridges : [];
  if (!list.length && (stored.bridgeUrl || stored.token)) {
    list = [{ url: stored.bridgeUrl || DEFAULT_BRIDGE_URL, token: stored.token || "" }];
  }
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
    seen.add(url);
    bridges.push({ url, token });
  }
  // Persist the list; drop the legacy single-bridge keys.
  await chrome.storage.local.set({ bridges });
  await chrome.storage.local.remove(["bridgeUrl", "token"]);
  const withToken = bridges.filter((b) => b.token).length;
  setStatus(`Saved ${bridges.length} bridge(s) (${withToken} with a token).`, "ok");
}

addButton.addEventListener("click", () => addRow("", ""));
saveButton.addEventListener("click", save);

load();
