'use strict';

const test = require('node:test');
const assert = require('node:assert');

// The function only needs firebase-functions to build its handler; loading the
// real module here would require the whole Functions runtime.
const Module = require('node:module');
const load = Module._load;
Module._load = function (request, ...rest) {
  if (request === 'firebase-functions/v2/https') {
    return { onRequest: (options, fn) => Object.assign(fn, { options }) };
  }
  return load.call(this, request, ...rest);
};

const { downloadApk, _resolveTarget, _handle } = require('../index.js');

const GOOD = 'https://spendsense-ota-2026.web.app/releases/spendsense-2.0.21+46.apk';

/** Minimal Express-like response that records what the handler did. */
function recorder() {
  const res = { code: 200, body: null, location: null, headers: {} };
  res.set = (key, value) => {
    res.headers[key] = value;
    return res;
  };
  res.status = (code) => {
    res.code = code;
    return res;
  };
  res.send = (body) => {
    res.body = body;
    return res;
  };
  res.redirect = (code, url) => {
    res.code = code;
    res.location = url;
    return res;
  };
  return res;
}

/** Runs the handler against a fabricated manifest response. */
async function run({ manifest, ok = true, method = 'GET', throwOnFetch = null }) {
  const realFetch = global.fetch;
  global.fetch = async () => {
    if (throwOnFetch) throw throwOnFetch;
    return { ok, json: async () => manifest };
  };
  const res = recorder();
  try {
    await _handle({ method }, res);
  } finally {
    global.fetch = realFetch;
  }
  return res;
}

test('redirects to the APK named by the manifest', async () => {
  const res = await run({ manifest: { downloadUrl: GOOD } });
  assert.strictEqual(res.code, 302);
  assert.strictEqual(res.location, GOOD);
  assert.strictEqual(res.headers['Content-Disposition'], 'attachment; filename="spendsense.apk"');
  // A visitor arriving just after a release must not be pinned to the old
  // build. A cached 302 is exactly that: the browser would keep replaying the
  // redirect it saw first, even after the manifest moved on. The APK it points
  // at is immutable and cached separately, so the redirect never needs reuse.
  assert.match(res.headers['Cache-Control'], /no-store/);
  assert.match(res.headers['Cache-Control'], /max-age=0/);
});

test('refuses a manifest that points at another host', async () => {
  const res = await run({ manifest: { downloadUrl: 'https://evil.example/releases/x.apk' } });
  assert.strictEqual(res.code, 502);
  assert.ok(!res.location);
});

test('refuses a manifest that points at a non-APK path', async () => {
  const res = await run({ manifest: { downloadUrl: 'https://spendsense-ota-2026.web.app/manifest.json' } });
  assert.strictEqual(res.code, 502);
});

test('refuses plain http', async () => {
  const res = await run({ manifest: { downloadUrl: GOOD.replace('https:', 'http:') } });
  assert.strictEqual(res.code, 502);
});

test('treats a missing downloadUrl as unavailable', async () => {
  const res = await run({ manifest: {} });
  assert.strictEqual(res.code, 502);
});

test('reports a manifest fetch failure instead of guessing a URL', async () => {
  const res = await run({ manifest: null, ok: false });
  assert.strictEqual(res.code, 502);
  assert.strictEqual(res.headers['Content-Disposition'], undefined);
});

test('survives a fetch that throws', async () => {
  const res = await run({ manifest: null, throwOnFetch: Object.assign(new Error('boom'), { name: 'AbortError' }) });
  assert.strictEqual(res.code, 502);
});

test('answers 405 for anything that is not a download', async () => {
  const res = await run({ manifest: { downloadUrl: GOOD }, method: 'POST' });
  assert.strictEqual(res.code, 405);
  assert.strictEqual(res.headers.Allow, 'GET, HEAD');
});

test('accepts HEAD so link checkers can verify the target', async () => {
  const res = await run({ manifest: { downloadUrl: GOOD }, method: 'HEAD' });
  assert.strictEqual(res.code, 302);
});

test('resolveTarget rejects malformed input', () => {
  for (const bad of [null, undefined, {}, { downloadUrl: 42 }, { downloadUrl: 'not a url' }, { downloadUrl: '' }]) {
    assert.strictEqual(_resolveTarget(bad), null);
  }
  assert.strictEqual(_resolveTarget({ downloadUrl: GOOD }).toString(), GOOD);
});

test('the http handler is public so a browser can reach it', () => {
  assert.strictEqual(downloadApk.options.invoker, 'public');
  // The rewrite in firebase.json must name this region.
  assert.strictEqual(downloadApk.options.region, 'us-central1');
});
