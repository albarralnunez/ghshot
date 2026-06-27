"use strict";

const DEFAULT_BRIDGE_URL = "http://127.0.0.1:41330";

const bridgeUrlInput = document.getElementById("bridgeUrl");
const tokenInput = document.getElementById("token");
const saveButton = document.getElementById("save");
const testButton = document.getElementById("test");
const statusEl = document.getElementById("status");

function setStatus(message, kind) {
  statusEl.textContent = message;
  statusEl.className = kind || "";
}

function normalizeUrl(url) {
  return (url || "").trim().replace(/\/+$/, "");
}

async function load() {
  const stored = await chrome.storage.local.get(["bridgeUrl", "token"]);
  bridgeUrlInput.value = stored.bridgeUrl || DEFAULT_BRIDGE_URL;
  tokenInput.value = stored.token || "";
}

async function save() {
  const bridgeUrl = normalizeUrl(bridgeUrlInput.value) || DEFAULT_BRIDGE_URL;
  const token = tokenInput.value.trim();
  await chrome.storage.local.set({ bridgeUrl, token });
  bridgeUrlInput.value = bridgeUrl;
  setStatus("Saved.", "ok");
}

async function testConnection() {
  const bridgeUrl = normalizeUrl(bridgeUrlInput.value) || DEFAULT_BRIDGE_URL;
  setStatus("Testing…", "");
  try {
    const resp = await fetch(bridgeUrl + "/healthz");
    if (!resp.ok) {
      setStatus(`Bridge responded HTTP ${resp.status}`, "err");
      return;
    }
    const data = await resp.json();
    if (data && data.ok) {
      setStatus(`OK — bridge version ${data.version || "unknown"}`, "ok");
    } else {
      setStatus("Unexpected response from bridge.", "err");
    }
  } catch (err) {
    setStatus(`Cannot reach bridge: ${String(err)}`, "err");
  }
}

saveButton.addEventListener("click", save);
testButton.addEventListener("click", testConnection);

load();
