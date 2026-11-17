'use strict';

// Regression tests for the hosting recovery-inventory path classification.
//
// The inventory capture runs against a Hosting release that contains both the
// production OTA payload and the staging channel's OTA payload. Production is
// the only thing captured into the recovery baseline; staging files must be
// recognised (so capture does not abort) but never captured. Both sets are
// deliberately narrow: an unexpected path must still fail closed.
//
// Run with: node --test tool/test_capture_hosting_inventory.js

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  isProductionPayload,
  isStagingManifest,
  isStagingApk,
  isStagingPayload,
  isKnownNonPayload,
  classifyFiles,
} = require('./capture_hosting_inventory');

const PROD_MANIFEST = '/manifest.json';
const PROD_APK = '/releases/spendsense-2.0.26+52.apk';
const STAGING_MANIFEST = '/staging/manifest.json';
const STAGING_APK = '/staging/releases/spendsense-2.0.26+51.apk';

test('valid production manifest is production payload only', () => {
  assert.equal(isProductionPayload(PROD_MANIFEST), true);
  assert.equal(isStagingPayload(PROD_MANIFEST), false);
  assert.equal(isKnownNonPayload(PROD_MANIFEST), false);
});

test('valid production APK is production payload only', () => {
  assert.equal(isProductionPayload(PROD_APK), true);
  assert.equal(isProductionPayload('/releases/spendsense-2.0.26+51.apk'), true);
  assert.equal(isStagingPayload(PROD_APK), false);
  assert.equal(isKnownNonPayload(PROD_APK), false);
});

test('valid staging manifest is recognised and never a production payload', () => {
  assert.equal(isStagingManifest(STAGING_MANIFEST), true);
  assert.equal(isStagingPayload(STAGING_MANIFEST), true);
  assert.equal(isProductionPayload(STAGING_MANIFEST), false);
  assert.equal(isKnownNonPayload(STAGING_MANIFEST), true);
});

test('valid staging APK is recognised and never a production payload', () => {
  assert.equal(isStagingApk(STAGING_APK), true);
  assert.equal(isStagingPayload(STAGING_APK), true);
  assert.equal(isProductionPayload(STAGING_APK), false);
  assert.equal(isKnownNonPayload(STAGING_APK), true);
});

test('unexpected staging paths are rejected', () => {
  const bad = [
    '/staging/manifest.json.bak',
    '/staging/notes.txt',
    '/staging/MANIFEST.json',
    '/staging/releases/readme.md',
    '/staging/releases/spendsense.apk.bak',
    '/staging2/manifest.json',
    '/stagingx/releases/spendsense.apk',
  ];
  for (const p of bad) {
    assert.equal(isStagingPayload(p), false, p);
    assert.equal(isKnownNonPayload(p), false, p);
  }
});

test('unexpected production paths are rejected', () => {
  const bad = [
    '/manifest.json.bak',
    '/releases/latest.apk', // a hosting rewrite, not an uploaded file
    '/releases/readme.md',
    '/releases/spendsense.apk.bak',
  ];
  for (const p of bad) {
    assert.equal(isProductionPayload(p), false, p);
  }
  assert.equal(isProductionPayload('/releases/sub/spendsense.apk'), false);
  assert.equal(isProductionPayload('/releases/../spendsense.apk'), false);
});

test('path traversal attempts are rejected', () => {
  const bad = [
    '/staging/releases/../manifest.json',
    '/staging/../manifest.json',
    '/staging/releases/..\\..\\evil.apk',
    '/staging/releases/%2e%2e/evil.apk',
    '/staging/releases/.hidden.apk',
    '/staging/releases/%2Fetc%2Fpasswd.apk',
    '/staging/releases/..apk',
  ];
  for (const p of bad) {
    assert.equal(isStagingPayload(p), false, p);
    assert.equal(isKnownNonPayload(p), false, p);
  }
});

test('arbitrary nested directories are rejected', () => {
  const bad = [
    '/staging/releases/a/spendsense.apk',
    '/staging/foo/bar.apk',
    '/staging/releases/subdir/spendsense-2.0.26+51.apk',
    '/staging/a/b/c/d.apk',
  ];
  for (const p of bad) {
    assert.equal(isStagingPayload(p), false, p);
    assert.equal(isKnownNonPayload(p), false, p);
  }
});

test('duplicate and conflicting inventory entries are reported, never collapsed', () => {
  const files = [
    { path: STAGING_MANIFEST, status: 'ACTIVE' },
    { path: STAGING_MANIFEST, status: 'EXPIRED' },
    { path: PROD_APK, status: 'ACTIVE' },
    { path: PROD_APK, status: 'ACTIVE' },
  ];
  const { live, duplicates, inactive } = classifyFiles(files);
  assert.deepEqual(duplicates.sort(), [PROD_APK, STAGING_MANIFEST].sort());
  assert.equal(live.length, 2);
  assert.deepEqual(inactive, []);
});

test('production and staging classification stays separate', () => {
  for (const p of [PROD_MANIFEST, PROD_APK, STAGING_MANIFEST, STAGING_APK]) {
    const prod = isProductionPayload(p);
    const staging = isStagingPayload(p);
    assert.notEqual(prod, staging, `exactly one bucket for ${p}`);
  }
  assert.equal(isKnownNonPayload(STAGING_MANIFEST), true);
  assert.equal(isKnownNonPayload(STAGING_APK), true);
  assert.equal(isKnownNonPayload(PROD_MANIFEST), false);
  assert.equal(isKnownNonPayload(PROD_APK), false);
});

test('current live release classifies with no unknown paths and captures staging never', () => {
  const isGenerated = (p) => p.startsWith('/__/firebase/');
  const livePaths = [
    PROD_MANIFEST,
    PROD_APK,
    STAGING_MANIFEST,
    STAGING_APK,
    '/index.html',
    '/404.html',
    '/landing.css',
    '/legal/privacy.html',
    '/site/main.dart.js',
    '/__/firebase/init.json',
  ];
  const unknown = livePaths.filter(
    (p) => !isGenerated(p) && !isProductionPayload(p) && !isKnownNonPayload(p),
  );
  assert.deepEqual(unknown, []);

  const captured = livePaths.filter(isProductionPayload);
  assert.deepEqual(captured, [PROD_MANIFEST, PROD_APK]);
  const staging = livePaths.filter(isStagingPayload);
  assert.deepEqual(staging, [STAGING_MANIFEST, STAGING_APK]);

  // A new, unrecognised staging file still fails closed.
  const withExtra = [...livePaths, '/staging/extra.json'];
  const stillUnknown = withExtra.filter(
    (p) => !isGenerated(p) && !isProductionPayload(p) && !isKnownNonPayload(p),
  );
  assert.deepEqual(stillUnknown, ['/staging/extra.json']);
});
