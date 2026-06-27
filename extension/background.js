// ghshot background service worker (MV3).
//
// Responsibilities:
//   1. Long-poll the local ghshot bridge (127.0.0.1) for upload jobs.
//   2. For each job, fetch the image blob from the bridge and upload it to
//      GitHub's user-attachments storage using THIS browser's authenticated
//      github.com session (credentials: "include"). No cookie extraction, no
//      stored token — the upload rides the user's real login.
//   3. Report the resulting inline URL (or an error) back to the bridge.
//
// MV3 service workers are killed when idle, so the poll loop is (re)started
// from onInstalled, onStartup, and a 1-minute alarm. The loop guards against
// running more than once concurrently.

"use strict";

const DEFAULT_BRIDGE_URL = "http://127.0.0.1:41330";
const TOKEN_HEADER = "X-Ghshot-Token";
const POLL_PATH = "/v1/poll";
const RESULT_PATH = "/v1/result";
const NETWORK_RETRY_MS = 3000;

// ---------------------------------------------------------------------------
// GitHub user-attachments upload.
//
// WARNING: This endpoint flow is UNDOCUMENTED and reverse-engineered from the
// github.com web UI's drag-and-drop image upload. GitHub may change the HTML
// attributes, field names, or the multi-step protocol at any time; if uploads
// start failing, re-inspect the network traffic of a manual image paste on a
// repo page and adjust the constants below.
// ---------------------------------------------------------------------------

// Regexes used to scrape the authenticated repo page for the upload secrets.
const RE_REPOSITORY_ID = [
  /name="repository_id"[^>]*\bvalue="(\d+)"/,
  /\bdata-upload-repository-id="(\d+)"/,
];
const RE_UPLOAD_POLICY_URL = /\bdata-upload-policy-url="([^"]+)"/;
const RE_UPLOAD_POLICY_TOKEN = [
  /\bdata-upload-policy-authenticity-token="([^"]+)"/,
  /name="authenticity_token"[^>]*\bvalue="([^"]+)"/,
];
const RE_LOGIN_FORM = /<form[^>]+action="\/session"/i;

const DEFAULT_UPLOAD_POLICY_URL = "/upload/policies/assets";
const GITHUB_ORIGIN = "https://github.com";

// Multipart field names sent to the policy endpoint (step 2).
const POLICY_FIELDS = {
  name: "name",
  size: "size",
  contentType: "content_type",
  repositoryId: "repository_id",
  authenticityToken: "authenticity_token",
};

function firstMatch(text, patterns) {
  const list = Array.isArray(patterns) ? patterns : [patterns];
  for (const re of list) {
    const m = text.match(re);
    if (m && m[1]) return m[1];
  }
  return null;
}

function guessContentType(filename, blob) {
  if (blob && blob.type) return blob.type;
  const lower = (filename || "").toLowerCase();
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  if (lower.endsWith(".gif")) return "image/gif";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".svg")) return "image/svg+xml";
  return "application/octet-stream";
}

// Performs the full GitHub user-attachments upload and returns the final
// github.com/user-attachments/assets/<uuid> href. Throws an Error on any
// failure with an explicit message.
const RE_REPO = /^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\/[A-Za-z0-9._-]+$/;

async function uploadToGitHub(repo, blob, filename) {
  // Defense in depth: the bridge already validates this, but never build a
  // github.com URL from an unvalidated repo string.
  if (!RE_REPO.test(repo)) {
    throw new Error(`invalid repo "${repo}" (expected owner/name)`);
  }
  // Step 1: scrape the authenticated repo page for upload secrets.
  console.debug("[ghshot] step 1: fetching repo page for", repo);
  const [repoOwner, repoName] = repo.split("/");
  const pageUrl = `${GITHUB_ORIGIN}/${encodeURIComponent(repoOwner)}/${encodeURIComponent(repoName)}`;
  const pageResp = await fetch(pageUrl, {
    credentials: "include",
    headers: { Accept: "text/html" },
  });
  if (!pageResp.ok) {
    throw new Error(`failed to load ${pageUrl}: HTTP ${pageResp.status}`);
  }
  const html = await pageResp.text();

  const repositoryId = firstMatch(html, RE_REPOSITORY_ID);
  if (!repositoryId || RE_LOGIN_FORM.test(html)) {
    throw new Error("not signed in to github.com in this browser");
  }
  const policyUrl = firstMatch(html, RE_UPLOAD_POLICY_URL) || DEFAULT_UPLOAD_POLICY_URL;
  const policyToken = firstMatch(html, RE_UPLOAD_POLICY_TOKEN);
  if (!policyToken) {
    throw new Error("could not find upload authenticity token on repo page");
  }
  const contentType = guessContentType(filename, blob);
  console.debug("[ghshot] step 1 ok: repositoryId=%s policyUrl=%s", repositoryId, policyUrl);

  // Step 2: ask GitHub for an upload policy (S3 form fields + asset href).
  console.debug("[ghshot] step 2: requesting upload policy");
  const policyForm = new FormData();
  policyForm.append(POLICY_FIELDS.name, filename);
  policyForm.append(POLICY_FIELDS.size, String(blob.size));
  policyForm.append(POLICY_FIELDS.contentType, contentType);
  policyForm.append(POLICY_FIELDS.repositoryId, repositoryId);
  policyForm.append(POLICY_FIELDS.authenticityToken, policyToken);

  const policyResp = await fetch(`${GITHUB_ORIGIN}${policyUrl}`, {
    method: "POST",
    credentials: "include",
    headers: {
      "X-Requested-With": "XMLHttpRequest",
      Accept: "application/json",
    },
    body: policyForm,
  });
  if (!policyResp.ok) {
    const detail = await policyResp.text().catch(() => "");
    throw new Error(`upload policy request failed: HTTP ${policyResp.status} ${detail.slice(0, 200)}`);
  }
  const p = await policyResp.json();
  if (!p || !p.upload_url || !p.form || !p.asset || !p.asset.href) {
    throw new Error("upload policy response missing expected fields");
  }
  console.debug("[ghshot] step 2 ok: asset href=%s", p.asset.href);

  // Step 3: POST the bytes to the S3 (no github credentials here).
  console.debug("[ghshot] step 3: uploading bytes to storage");
  const s3Form = new FormData();
  for (const [key, value] of Object.entries(p.form)) {
    s3Form.append(key, value);
  }
  s3Form.append("file", blob, filename);

  const s3Resp = await fetch(p.upload_url, {
    method: "POST",
    body: s3Form,
    // Deliberately NO credentials: this is a plain S3 form POST.
  });
  if (s3Resp.status !== 201 && s3Resp.status !== 204 && !s3Resp.ok) {
    throw new Error(`storage upload failed: HTTP ${s3Resp.status}`);
  }
  console.debug("[ghshot] step 3 ok: storage accepted (HTTP %s)", s3Resp.status);

  // Step 4: finalize the asset back on github.com.
  console.debug("[ghshot] step 4: finalizing asset");
  const finalizeForm = new FormData();
  finalizeForm.append("authenticity_token", p.asset_upload_authenticity_token);

  const finalizeResp = await fetch(`${GITHUB_ORIGIN}${p.asset_upload_url}`, {
    method: "PUT",
    credentials: "include",
    headers: { Accept: "application/json" },
    body: finalizeForm,
  });
  if (!finalizeResp.ok) {
    throw new Error(`asset finalize failed: HTTP ${finalizeResp.status}`);
  }
  console.debug("[ghshot] step 4 ok: asset finalized");

  // Step 5: the asset href renders inline and is access-controlled to the repo.
  return p.asset.href;
}

// ---------------------------------------------------------------------------
// Bridge config + long-poll loops (one per configured bridge).
//
// Multiple bridges are supported: e.g. a local bridge on 127.0.0.1 and a remote
// bridge on another machine over Tailscale. Each is polled independently; a job
// is fetched from, and its result posted back to, the bridge it came from.
// ---------------------------------------------------------------------------

// Read the configured bridges as [{ url, token }]. Migrates the legacy single
// { bridgeUrl, token } shape to a one-element list.
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

// Reconcile running loops with the configured bridges: start loops for new
// bridges, let loops for removed bridges exit on their next iteration.
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
      pollBridge(b.url, gen);
    }
  }
}

async function pollBridge(url, gen) {
  console.debug("[ghshot] loop start:", url);
  try {
    while (RUNNING.get(url) === gen) {
      // Re-read the token each iteration so edits apply without a restart.
      const b = (await getBridges()).find((x) => x.url === url);
      if (!b) return; // removed from config
      const token = b.token;

      let pollResp;
      try {
        pollResp = await fetch(url + POLL_PATH, { headers: { [TOKEN_HEADER]: token } });
      } catch (err) {
        console.debug("[ghshot] poll network error (%s), backing off:", url, String(err));
        await sleep(NETWORK_RETRY_MS);
        continue;
      }
      if (pollResp.status === 204) continue; // no job in the long-poll window
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
    const blobResp = await fetch(bridgeUrl + job.blob, {
      headers: { [TOKEN_HEADER]: token },
    });
    if (!blobResp.ok) {
      throw new Error(`failed to fetch image from bridge: HTTP ${blobResp.status}`);
    }
    const blob = await blobResp.blob();
    const url = await uploadToGitHub(job.repo, blob, job.filename);
    console.debug("[ghshot] job %s succeeded: %s", job.id, url);
    result = { id: job.id, url };
  } catch (err) {
    console.debug("[ghshot] job %s failed:", job.id, String(err));
    result = { id: job.id, error: String(err && err.message ? err.message : err) };
  }

  try {
    await fetch(bridgeUrl + RESULT_PATH, {
      method: "POST",
      headers: {
        [TOKEN_HEADER]: token,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(result),
    });
  } catch (err) {
    console.debug("[ghshot] failed to post result for job %s:", job.id, String(err));
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// Lifecycle hooks: keep the loop alive across service-worker restarts.
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
  if (alarm.name === "ghshot-poll") {
    supervise();
  }
});

// React to Options changes (bridges added/removed/edited) without a restart.
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "local") supervise();
});

// Kick the loops on initial worker evaluation too.
supervise();
