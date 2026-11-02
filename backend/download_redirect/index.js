'use strict';

// Serves a stable download URL for the landing page.
//
// The "Download APK" button points at /releases/latest.apk. That file is never
// uploaded: Hosting reserves /releases/** for the immutable, versioned APKs and
// `firebase deploy` replaces the whole Hosting release each time, so a copied
// file would go stale the moment a new build shipped. Instead this function
// reads the same manifest.json that installed builds use to self-update, and
// redirects to the one APK that manifest names — so the button and the in-app
// updater can never advertise different versions.
//
// Integrity is not duplicated here. The manifest and the APK are produced by the
// OTA publish workflow only after the APK's signing certificate has been checked
// against the pinned release certificate.
//
// The arguments are the plain request/response pair so the routing rules below
// can be unit-tested without the Functions runtime.
const functions = require('firebase-functions/v2/https');

const MANIFEST_URL =
  process.env.OTA_MANIFEST_URL ||
  'https://spendsense-ota-2026.web.app/manifest.json';

// The device validates the manifest's downloadUrl against the same origin and an
// `.apk` path before installing. A browser gets the same two checks, so a
// tampered manifest cannot turn this button into a redirect to anywhere.
const ALLOWED_HOSTS = new Set(['spendsense-ota-2026.web.app']);
const MANIFEST_TIMEOUT_MS = 5000;

const UNAVAILABLE =
  'The release download is unavailable right now. Please try again in a minute.';

function resolveTarget(manifest) {
  const raw = manifest && manifest.downloadUrl;
  if (typeof raw !== 'string' || raw.length === 0) return null;

  let url;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:') return null;
  if (!ALLOWED_HOSTS.has(url.hostname)) return null;
  if (!url.pathname.toLowerCase().endsWith('.apk')) return null;
  return url;
}

async function handle(req, res) {
  // Only the button (a top-level GET) is served. HEAD lets link checkers verify
  // the target without pulling 65 MB.
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.set('Allow', 'GET, HEAD');
    res.status(405).send('Method Not Allowed');
    return;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), MANIFEST_TIMEOUT_MS);

  try {
    const response = await fetch(MANIFEST_URL, {
      signal: controller.signal,
      headers: { accept: 'application/json' },
    });
    if (!response.ok) {
      res.status(502).send(UNAVAILABLE);
      return;
    }

    const target = resolveTarget(await response.json());
    if (!target) {
      res.status(502).send(UNAVAILABLE);
      return;
    }

    // Short cache: someone arriving just after a release must not be pinned to
    // the previous build, but the origin should not be hit on every tap either.
    res.set('Cache-Control', 'public, max-age=60');
    // `download=` makes the browser save the file instead of navigating to it.
    res.set('Content-Disposition', 'attachment; filename="spendsense.apk"');
    res.redirect(302, target.toString());
  } catch (error) {
    // Logged by name only: the manifest body is not ours to reveal in a log.
    console.error('download redirect failed:', error && (error.name || 'error'));
    res.status(502).send(UNAVAILABLE);
  } finally {
    clearTimeout(timer);
  }
}

exports.downloadApk = functions.onRequest(
  { region: 'us-central1', invoker: 'public' },
  handle,
);

// Exported for the test in ./test.
exports._resolveTarget = resolveTarget;
exports._handle = handle;
