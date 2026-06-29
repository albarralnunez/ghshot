// ghshot background service worker (MV3).
//
// Responsibilities:
//   1. Long-poll the configured ghshot bridge(s) for upload jobs.
//   2. For each job, fetch the image blob from the bridge and upload it to
//      GitHub's user-attachments storage using THIS browser's authenticated
//      github.com session. The upload runs INSIDE a github.com tab (via
//      chrome.scripting.executeScript), so the requests are first-party to
//      github.com and carry the user's real session cookies — this works on
//      private repos and is not affected by third-party-cookie blocking, which
//      strips cookies from a service-worker cross-site fetch.
//   3. Report the resulting inline URL (or an error) back to the bridge.
//
// MV3 service workers are killed when idle, so the poll loops are (re)started
// from onInstalled, onStartup, a 1-minute alarm, and storage changes.

"use strict";

const DEFAULT_BRIDGE_URL = "http://127.0.0.1:41330";
const TOKEN_HEADER = "X-Ghshot-Token";
const POLL_PATH = "/v1/poll";
const RESULT_PATH = "/v1/result";
const NETWORK_RETRY_MS = 3000;

const RE_REPO = /^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\/[A-Za-z0-9._-]+$/;

// ---------------------------------------------------------------------------
// GitHub user-attachments upload — driven from a github.com tab.
//
// WARNING: This endpoint flow is UNDOCUMENTED and reverse-engineered from the
// github.com web UI's image upload. If uploads start failing, re-inspect the
// network traffic of a manual image paste on a repo page and adjust pageUpload.
// ---------------------------------------------------------------------------

function blobToBase64(blob) {
  return blob.arrayBuffer().then((buf) => {
    const bytes = new Uint8Array(buf);
    let s = "";
    const CHUNK = 0x8000;
    for (let i = 0; i < bytes.length; i += CHUNK) {
      s += String.fromCharCode.apply(null, bytes.subarray(i, i + CHUNK));
    }
    return btoa(s);
  });
}

function waitTabComplete(tabId) {
  return new Promise((resolve) => {
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      chrome.tabs.onUpdated.removeListener(listener);
      resolve();
    };
    const listener = (id, info) => {
      if (id === tabId && info.status === "complete") finish();
    };
    // Attach the listener BEFORE the status re-check to avoid missing a
    // "complete" event fired in between (race / hang).
    chrome.tabs.onUpdated.addListener(listener);
    chrome.tabs.get(tabId, (t) => {
      if (chrome.runtime.lastError || (t && t.status === "complete")) finish();
    });
    setTimeout(finish, 15000); // never hang forever
  });
}

async function injectUpload(tabId, owner, repo, base64, filename, mime) {
  const injection = await chrome.scripting.executeScript({
    target: { tabId },
    func: pageUpload,
    args: [owner, repo, base64, filename, mime || ""],
  });
  return injection && injection[0] ? injection[0].result : null;
}

// A thrown executeScript error that means "this tab can't be scripted right now"
// (discarded, showing an error page, chrome:// page, closed) — as opposed to a
// genuine upload failure returned by pageUpload.
function isTabStateError(msg) {
  return /error page|no tab with id|cannot be scripted|cannot access|no frame|frame with id|chrome:\/\/|the tab was closed|extension manifest must request permission/i.test(
    msg
  );
}

// Run the upload from a github.com tab so the requests are first-party (carry
// the session). Prefer an already-open, loaded github.com tab; otherwise open a
// background tab on the repo, use it, and close it.
async function uploadViaTab(owner, repo, base64, filename, mime) {
  const repoUrl = `https://github.com/${owner}/${repo}`;

  let tabs = [];
  try {
    tabs = await chrome.tabs.query({ url: "https://github.com/*" });
  } catch (e) {
    tabs = [];
  }
  const candidates = tabs.filter((t) => t && t.id != null && !t.discarded && t.status !== "unloaded");

  for (const t of candidates) {
    try {
      const r = await injectUpload(t.id, owner, repo, base64, filename, mime);
      if (r && r.ok) return r.href;
      // pageUpload ran but reported a real failure (e.g. signed out) — surface it,
      // don't keep retrying other tabs (they'd give the same answer).
      if (r && r.error) throw new Error(r.error);
    } catch (e) {
      const msg = String((e && e.message) || e);
      if (!isTabStateError(msg)) throw e; // genuine upload error
      // else: bad tab state — try the next candidate / a fresh tab
    }
  }

  // No usable existing tab: open a dedicated background tab on the repo.
  const tab = await chrome.tabs.create({ url: repoUrl, active: false });
  try {
    await waitTabComplete(tab.id);
    const info = await chrome.tabs.get(tab.id).catch(() => null);
    if (!info || !/^https:\/\/github\.com\//.test(info.url || "")) {
      await chrome.tabs.update(tab.id, { url: repoUrl });
      await waitTabComplete(tab.id);
    }
    let r;
    try {
      r = await injectUpload(tab.id, owner, repo, base64, filename, mime);
    } catch (e) {
      const msg = String((e && e.message) || e);
      if (isTabStateError(msg)) {
        throw new Error("could not run the upload in a github.com tab — open a github.com tab (signed in) and retry");
      }
      throw e;
    }
    if (!r || !r.ok) {
      throw new Error((r && r.error) || "upload failed in page context");
    }
    return r.href;
  } finally {
    try {
      await chrome.tabs.remove(tab.id);
    } catch (e) {
      /* ignore */
    }
  }
}

// Runs INSIDE github.com (first-party). MUST be fully self-contained — it is
// serialized and injected, so it may not reference any outer-scope identifier.
async function pageUpload(owner, repo, base64, filename, mime) {
  try {
    const bin = atob(base64);
    const u = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
    const ctype = mime || "application/octet-stream";
    const blob = new Blob([u], { type: ctype });

    const m1 = (s, re) => {
      const m = s.match(re);
      return m ? m[1] : null;
    };

    // Fetch the repo page same-origin (carries the session cookies regardless
    // of third-party-cookie policy).
    const pageResp = await fetch(`/${owner}/${repo}`, {
      credentials: "include",
      headers: { Accept: "text/html" },
    });
    const html = await pageResp.text();
    const signedIn = /<meta name="user-login" content="[^"]+"/.test(html);
    if (pageResp.status === 404 || /\/login(\?|$)/.test(pageResp.url) || !signedIn) {
      return { ok: false, error: `not signed in to github.com, or no access to ${owner}/${repo}` };
    }

    const repoId =
      m1(html, /name="octolytics-dimension-repository_id"\s+content="(\d+)"/) ||
      m1(html, /name="hovercard-subject-tag"\s+content="repository:(\d+)"/) ||
      m1(html, /\bdata-upload-repository-id="(\d+)"/) ||
      m1(html, /name="repository_id"[^>]*\bvalue="(\d+)"/);

    let uploadToken =
      m1(html, /"uploadToken":"([^"]+)"/) ||
      m1(html, /\bdata-upload-policy-authenticity-token="([^"]+)"/) ||
      m1(html, /<meta name="csrf-token" content="([^"]+)"/);

    // Fallback: a comment form (issues/new) reliably carries an upload token.
    if (repoId && !uploadToken) {
      try {
        const alt = await (await fetch(`/${owner}/${repo}/issues/new`, {
          credentials: "include",
          headers: { Accept: "text/html" },
        })).text();
        uploadToken =
          m1(alt, /"uploadToken":"([^"]+)"/) ||
          m1(alt, /name="authenticity_token"[^>]*\bvalue="([^"]+)"/) ||
          m1(alt, /<meta name="csrf-token" content="([^"]+)"/);
      } catch (e) {
        /* ignore */
      }
    }

    if (!repoId || !uploadToken) {
      return { ok: false, error: "could not find upload tokens on the repo page (GitHub HTML changed)" };
    }

    const fetchNonce = m1(html, /name="fetch-nonce" content="([^"]+)"/);
    const release = m1(html, /name="release" content="([^"]+)"/);

    // Step 1: request an upload policy.
    const policyForm = new FormData();
    policyForm.append("name", filename);
    policyForm.append("size", String(blob.size));
    policyForm.append("content_type", ctype);
    policyForm.append("repository_id", repoId);
    policyForm.append("authenticity_token", uploadToken);
    const policyHeaders = { Accept: "application/json", "X-Requested-With": "XMLHttpRequest" };
    if (fetchNonce) {
      policyHeaders["GitHub-Verified-Fetch"] = "true";
      policyHeaders["X-Fetch-Nonce"] = fetchNonce;
    }
    if (release) policyHeaders["X-GitHub-Client-Version"] = release;

    const policyResp = await fetch("/upload/policies/assets", {
      method: "POST",
      credentials: "include",
      headers: policyHeaders,
      body: policyForm,
    });
    if (!policyResp.ok) {
      const detail = await policyResp.text().catch(() => "");
      return { ok: false, error: `upload policy failed: HTTP ${policyResp.status} ${detail.slice(0, 200)}` };
    }
    const p = await policyResp.json();
    if (!p || !p.upload_url || !p.form || !p.asset || !p.asset.href ||
        !p.asset_upload_url || !p.asset_upload_authenticity_token) {
      return { ok: false, error: "upload policy response missing expected fields" };
    }

    // Step 2: POST the bytes to storage (no github credentials — plain form POST).
    const storeForm = new FormData();
    for (const k in p.form) storeForm.append(k, p.form[k]);
    storeForm.append("file", blob, filename);
    const storeResp = await fetch(p.upload_url, { method: "POST", body: storeForm });
    if (storeResp.status !== 201 && storeResp.status !== 204 && !storeResp.ok) {
      return { ok: false, error: `storage upload failed: HTTP ${storeResp.status}` };
    }

    // Step 3: finalize the asset on github.com.
    const finalizeUrl = p.asset_upload_url.startsWith("http")
      ? p.asset_upload_url
      : `https://github.com${p.asset_upload_url}`;
    const finalizeForm = new FormData();
    finalizeForm.append("authenticity_token", p.asset_upload_authenticity_token);
    const finalizeResp = await fetch(finalizeUrl, {
      method: "PUT",
      credentials: "include",
      headers: { Accept: "application/json", "X-Requested-With": "XMLHttpRequest" },
      body: finalizeForm,
    });
    if (!finalizeResp.ok) {
      return { ok: false, error: `asset finalize failed: HTTP ${finalizeResp.status}` };
    }

    return { ok: true, href: p.asset.href };
  } catch (e) {
    return { ok: false, error: String((e && e.message) || e) };
  }
}

// ---------------------------------------------------------------------------
// Bridge config + long-poll loops (one per configured bridge).
//
// Multiple bridges are supported: e.g. a local bridge on 127.0.0.1 and a remote
// bridge on another machine. Each is polled independently; a job is fetched
// from, and its result posted back to, the bridge it came from.
// ---------------------------------------------------------------------------

async function getBridges() {
  const stored = await chrome.storage.local.get(["bridges", "bridgeUrl", "token"]);
  let list = Array.isArray(stored.bridges) ? stored.bridges : [];
  if (!list.length && (stored.bridgeUrl || stored.token)) {
    list = [{ url: stored.bridgeUrl || DEFAULT_BRIDGE_URL, token: stored.token || "" }];
  }
  const seen = new Set();
  const out = [];
  for (const b of list) {
    const url = String((b && b.url) || "").trim().replace(/\/+$/, "");
    const token = String((b && b.token) || "").trim();
    if (!url || !token || seen.has(url)) continue;
    seen.add(url);
    out.push({ url, token });
  }
  return out;
}

// url -> generation. A loop runs while RUNNING.get(url) === its own generation.
const RUNNING = new Map();
let GENERATION = 0;

async function supervise() {
  const bridges = await getBridges();
  const wanted = new Set(bridges.map((b) => b.url));
  for (const url of [...RUNNING.keys()]) {
    if (!wanted.has(url)) RUNNING.delete(url);
  }
  for (const b of bridges) {
    if (!RUNNING.has(b.url)) {
      const gen = ++GENERATION;
      RUNNING.set(b.url, gen);
      pollBridge(b.url, gen).catch((e) => {
        console.debug("[ghshot] loop crashed:", b.url, String(e));
        if (RUNNING.get(b.url) === gen) RUNNING.delete(b.url);
      });
    }
  }
}

async function pollBridge(url, gen) {
  console.debug("[ghshot] loop start:", url);
  try {
    while (RUNNING.get(url) === gen) {
      const b = (await getBridges()).find((x) => x.url === url);
      if (!b) return; // removed from config
      const token = b.token;

      let pollResp;
      try {
        // redirect:"error" so the X-Ghshot-Token header is never forwarded to a
        // redirect target (custom headers survive cross-origin redirects).
        pollResp = await fetch(url + POLL_PATH, { headers: { [TOKEN_HEADER]: token }, redirect: "error" });
      } catch (err) {
        console.debug("[ghshot] poll network error (%s), backing off:", url, String(err));
        await sleep(NETWORK_RETRY_MS);
        continue;
      }
      if (pollResp.status === 204) continue;
      if (!pollResp.ok) {
        console.debug("[ghshot] poll %s returned HTTP", url, pollResp.status);
        await sleep(NETWORK_RETRY_MS);
        continue;
      }
      let job;
      try {
        job = await pollResp.json();
      } catch (err) {
        console.debug("[ghshot] bad poll JSON from %s:", url, String(err));
        await sleep(NETWORK_RETRY_MS);
        continue;
      }
      await handleJob(url, token, job);
    }
  } finally {
    if (RUNNING.get(url) === gen) RUNNING.delete(url);
    console.debug("[ghshot] loop stop:", url);
  }
}

async function handleJob(bridgeUrl, token, job) {
  console.debug("[ghshot] job received:", job && job.id, job && job.repo, job && job.filename);
  let result;
  try {
    if (!RE_REPO.test((job && job.repo) || "")) {
      throw new Error(`invalid repo "${job && job.repo}" (expected owner/name)`);
    }
    const blobResp = await fetch(bridgeUrl + job.blob, { headers: { [TOKEN_HEADER]: token }, redirect: "error" });
    if (!blobResp.ok) {
      throw new Error(`failed to fetch image from bridge: HTTP ${blobResp.status}`);
    }
    const blob = await blobResp.blob();
    const base64 = await blobToBase64(blob);
    const [owner, repoName] = job.repo.split("/");
    const url = await uploadViaTab(owner, repoName, base64, job.filename, blob.type || "");
    console.debug("[ghshot] job %s succeeded: %s", job.id, url);
    result = { id: job.id, url };
  } catch (err) {
    console.debug("[ghshot] job %s failed:", job.id, String(err));
    result = { id: job.id, error: String(err && err.message ? err.message : err) };
  }

  try {
    await fetch(bridgeUrl + RESULT_PATH, {
      method: "POST",
      headers: { [TOKEN_HEADER]: token, "Content-Type": "application/json" },
      body: JSON.stringify(result),
      redirect: "error",
    });
  } catch (err) {
    console.debug("[ghshot] failed to post result for job %s:", job.id, String(err));
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// Lifecycle hooks: keep the loops alive across service-worker restarts.
// ---------------------------------------------------------------------------

chrome.alarms.create("ghshot-poll", { periodInMinutes: 1 });

chrome.runtime.onInstalled.addListener(() => {
  console.debug("[ghshot] onInstalled");
  supervise();
});

chrome.runtime.onStartup.addListener(() => {
  console.debug("[ghshot] onStartup");
  supervise();
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "ghshot-poll") supervise();
});

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "local") supervise();
});

supervise();
