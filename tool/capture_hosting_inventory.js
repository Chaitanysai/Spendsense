#!/usr/bin/env node
'use strict';

// Captures the authoritative production Hosting inventory before a staging
// deploy, and packages it as a recovery baseline.
//
//   node tool/capture_hosting_inventory.js --preflight
//   node tool/capture_hosting_inventory.js --output ota/recovery-baseline
//
// Why this exists: `firebase deploy` replaces the WHOLE Hosting release. A
// staging publish therefore republishes production too, so the staging payload
// must carry production's bytes. Those bytes live only on the live site - the
// Hosting API cannot return historical file contents - so they are downloaded
// here, verified, and retained as `release-recovery` before anything deploys.
//
// Two digests are in play and they are never interchangeable:
//   * the OTA manifest's `sha256` is the digest of the RAW APK bytes, and is
//     what an installed build checks before it will install;
//   * the Hosting API's per-file `hash` is sha256 over the gzip stream that
//     firebase-tools uploaded (level 9, gzip OS byte 0x03).
// APK integrity is decided by the manifest. The API hash is only used to prove
// the API agrees about which file is live, never to judge the bytes.
//
// Fail-closed: every check exits non-zero with a named code. Nothing is written
// until the inventory is complete and every APK verifies.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const https = require('https');
const zlib = require('zlib');

const PROJECT = 'spendsense-ota-2026';
const SITE = 'spendsense-ota-2026';
const ORIGIN = `https://${SITE}.web.app`;
const API = 'https://firebasehosting.googleapis.com/v1beta1';
const SITE_PATH = `projects/${PROJECT}/sites/${SITE}`;
const OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token';

// Google's installed-app OAuth client, the same one firebase-tools ships. The
// `firebase login:ci` refresh token is bound to it, so the exchange has to use
// it; it is a public identifier, not a credential.
const FIREBASE_CLI_CLIENT_ID =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const FIREBASE_CLI_CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

// Hosting generates these at serve time; they are in the file list but are not
// retrievable as bytes. Counted, never captured.
const isGenerated = (p) => p.startsWith('/__/firebase/');
// `/releases/latest.apk` is a Hosting rewrite to the downloadApk function, not
// an uploaded file. If a release ever listed it, downloading it would store a
// redirect body and SHA256SUMS would certify that as a production asset.
const isReservedRewrite = (p) => p === '/releases/latest.apk';
// The OTA payload. Everything else in the release is page chrome, already
// tracked in git and rebuildable from the repository. Production recognition is
// intentionally unchanged: the recovery baseline must describe production only.
const isProductionPayload = (p) =>
  p === '/manifest.json' || (/^\/releases\/[^/]+\.apk$/.test(p) && !isReservedRewrite(p));

// The staging channel shares this site, so its two OTA files appear in the live
// release alongside production's. Capture must *recognise* them as known (or a
// staging publish can never produce a recovery baseline) while never capturing
// them into production's baseline. The patterns are exact: one filename
// segment, an alphanumeric first character, no separators, no traversal, no
// encoded path, no arbitrary nesting. An unexpected /staging/ path still fails.
const STAGING_MANIFEST_PATH = '/staging/manifest.json';
const isStagingManifest = (p) => p === STAGING_MANIFEST_PATH;
const isStagingApk = (p) =>
  /^\/staging\/releases\/[A-Za-z0-9][A-Za-z0-9._+-]*\.apk$/.test(p);
const isStagingPayload = (p) => isStagingManifest(p) || isStagingApk(p);

// Paths that may be live without being production payload: repository-tracked
// page chrome and the staging channel's OTA files. Both are classified and
// accounted for, neither is captured.
const isKnownNonPayload = (p) =>
  p === '/index.html' ||
  p === '/404.html' ||
  p === '/landing.css' ||
  p.startsWith('/legal/') ||
  p.startsWith('/site/') ||
  isStagingPayload(p);

function fail(code, detail) {
  const err = new Error(code + (detail ? `: ${detail}` : ''));
  err.code = code;
  throw err;
}

function parseArgs(argv) {
  const opts = { preflight: false, output: null, fixture: null, expectVersion: null };
  for (let i = 0; i < argv.length; i += 1) {
    switch (argv[i]) {
      case '--preflight':
        opts.preflight = true;
        break;
      case '--output':
        opts.output = argv[++i];
        break;
      case '--fixture':
        // Offline test seam: a directory holding manifest.json and releases/.
        // No network, no credential. Used by the inventory tests.
        opts.fixture = argv[++i];
        break;
      case '--expect-version':
        opts.expectVersion = argv[++i];
        break;
      default:
        fail('INVENTORY_BAD_ARGUMENT', argv[i]);
    }
  }
  if (!opts.preflight && !opts.output && !opts.fixture) {
    fail('INVENTORY_BAD_ARGUMENT', 'pass --preflight, --fixture <dir>, or --output <dir>');
  }
  return opts;
}

function request(url, { method = 'GET', headers = {}, body = null } = {}) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, { method, headers }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
    });
    req.setTimeout(60000, () => req.destroy(new Error('timeout')));
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

// Fetches a file, following at most a few redirects but only within ORIGIN.
// `https.request` never follows a redirect by itself, so a 302 would otherwise
// be a hard failure, and following one blindly would let a tampered site or
// manifest redirect the capture to another host's bytes.
async function fetchBytes(url, { maxRedirects = 3 } = {}) {
  let current = url;
  for (let hops = 0; hops <= maxRedirects; hops += 1) {
    const res = await request(current);
    if ([301, 302, 303, 307, 308].includes(res.status) && res.headers.location) {
      const next = new URL(res.headers.location, current);
      if (next.origin !== new URL(ORIGIN).origin) {
        fail('HOSTING_INVENTORY_REDIRECT_FOREIGN', `${current} redirected to ${next.origin}`);
      }
      current = next.toString();
      continue;
    }
    return { status: res.status, body: res.body, finalUrl: current };
  }
  fail('HOSTING_INVENTORY_REDIRECT_LOOP', `${url} exceeded ${maxRedirects} redirects`);
  return null;
}

// Exchanges the refresh token for a short-lived access token. Neither token is
// ever logged: the access token stays in this process.
async function accessToken(refreshToken) {
  if (!refreshToken) fail('HOSTING_INVENTORY_AUTH_MISSING', 'FIREBASE_TOKEN is not set');
  const form = new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
    client_id: FIREBASE_CLI_CLIENT_ID,
    client_secret: FIREBASE_CLI_CLIENT_SECRET,
  }).toString();
  const res = await request(OAUTH_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(form) },
    body: form,
  });
  if (res.status !== 200) {
    // The error body carries only an OAuth `error` code, never the token. The
    // code is what distinguishes a wrong client (invalid_client) from a
    // revoked or expired token (invalid_grant), which is the whole debugging
    // value of the message.
    let reason = '';
    try {
      const parsed = JSON.parse(res.body.toString('utf8'));
      if (parsed && typeof parsed.error === 'string') reason = ` (${parsed.error})`;
    } catch {
      // A non-JSON body adds nothing; report the status alone.
    }
    fail('HOSTING_INVENTORY_AUTH_INVALID', `token exchange returned HTTP ${res.status}${reason}`);
  }
  const parsed = JSON.parse(res.body.toString('utf8'));
  if (!parsed.access_token) fail('HOSTING_INVENTORY_AUTH_INVALID', 'token exchange returned no access token');
  return parsed.access_token;
}

async function apiGet(url, token) {
  const res = await request(url, { headers: { Authorization: `Bearer ${token}` } });
  if (res.status === 401 || res.status === 403) {
    fail('HOSTING_INVENTORY_UNAUTHORIZED', `HTTP ${res.status} from ${url.replace(API, '')}`);
  }
  if (res.status !== 200) {
    fail('HOSTING_INVENTORY_API_ERROR', `HTTP ${res.status} from ${url.replace(API, '')}`);
  }
  return JSON.parse(res.body.toString('utf8'));
}

// The releases list is newest-first and paginates at 20. Walking every page
// is what makes "newest DEPLOY" correct after the first page turns over.
async function newestDeployRelease(token) {
  let pageToken = null;
  let pages = 0;
  do {
    const url = `${API}/${SITE_PATH}/releases?pageSize=100${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''}`;
    const page = await apiGet(url, token);
    pages += 1;
    for (const release of page.releases || []) {
      if (release.type === 'DEPLOY' && release.version && release.version.name) {
        return { release, pages };
      }
    }
    pageToken = page.nextPageToken || null;
    if (pages > 50) fail('HOSTING_INVENTORY_PAGINATION_RUNAWAY', 'no DEPLOY release after 50 pages');
  } while (pageToken);
  fail('HOSTING_INVENTORY_NO_DEPLOY', 'no DEPLOY release found');
  return null;
}

// Returns every entry the files API lists, in page order and unfiltered.
//
// The count check that follows must see the raw list. `version.fileCount` is
// the version's own total, so filtering first would compare a filtered view to
// an unfiltered count: a healthy version with one duplicate path or one
// non-ACTIVE entry would look inconsistent and capture would refuse to run.
async function versionFilesRaw(versionName, token, { pageLimit = Infinity } = {}) {
  const files = [];
  let pageToken = null;
  let pages = 0;
  do {
    const url = `https://firebasehosting.googleapis.com/v1beta1/${versionName}/files?pageSize=100${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''}`;
    const page = await apiGet(url, token);
    pages += 1;
    files.push(...(page.files || []));
    pageToken = page.nextPageToken || null;
  } while (pageToken && pages < pageLimit);
  return { files, pages };
}

// Splits the raw list into the paths that are live and the paths that are not.
//
// Duplicates are rejected rather than collapsed. The API can in principle list
// one path twice with different statuses; silently taking the ACTIVE copy would
// pick which bytes are "production" without evidence, and `version.fileCount`
// counts entries, not paths. Refusing is the only answer that stays verifiable.
function classifyFiles(rawFiles) {
  const seen = new Map();
  const duplicates = [];
  const inactive = [];
  for (const file of rawFiles) {
    const prior = seen.get(file.path);
    if (prior) {
      if (!duplicates.includes(file.path)) duplicates.push(file.path);
      continue;
    }
    seen.set(file.path, file);
  }
  const live = [];
  for (const [p, file] of seen) {
    const status = file.status || 'ACTIVE';
    if (status !== 'ACTIVE') inactive.push(`${p} (${status})`);
    else live.push(file);
  }
  return { live, duplicates, inactive };
}

// The version's files, with the raw count proven against `fileCount` and every
// entry required to be ACTIVE and unique.
async function versionFiles(versionName, versionId, declaredCount, token) {
  const { files: raw, pages } = await versionFilesRaw(versionName, token);
  if (raw.length !== declaredCount) {
    fail('HOSTING_INVENTORY_FILE_COUNT_MISMATCH',
      `version ${versionId} declares ${declaredCount} file(s), the files API listed ${raw.length} across ${pages} page(s)`);
  }
  const { live, duplicates, inactive } = classifyFiles(raw);
  if (duplicates.length > 0) {
    fail('HOSTING_INVENTORY_DUPLICATE_PATH', `listed more than once: ${duplicates.join(', ')}`);
  }
  if (inactive.length > 0) {
    fail('HOSTING_INVENTORY_INACTIVE_FILE', `not ACTIVE: ${inactive.join(', ')}`);
  }
  return { live, raw, pages, inactive, duplicates };
}

const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Downloads a live path, retrying transient statuses. Throws a named failure
// rather than returning partial bytes.
async function download(url, { attempts = 4 } = {}) {
  let last = null;
  for (let i = 0; i < attempts; i += 1) {
    const res = await fetchBytes(url);
    if (res.status === 200) return res.body;
    if (res.status >= 500 || res.status === 429) {
      last = res.status;
      await sleep(2000 * (i + 1));
      continue;
    }
    fail('HOSTING_INVENTORY_FETCH_FAILED', `HTTP ${res.status} for ${url}`);
  }
  fail('HOSTING_INVENTORY_FETCH_FAILED', `HTTP ${last} after ${attempts} attempts for ${url}`);
  return null;
}

// Cross-check against the API's own digest. Only for the bytes exactly as
// uploaded: text is stored with LF endings, so a CRLF checkout will not match
// and that mismatch is not a capture failure. The value is evidence the API
// and the download describe the same file.
function apiHashMatches(bytes, apiHash) {
  if (!apiHash) return null;
  const copy = zlib.gzipSync(bytes, { level: 9 });
  copy[9] = 0x03;
  return sha256(copy) === apiHash;
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function mainCapture(opts) {
  const refresh = process.env.FIREBASE_TOKEN;
  let token;
  return (async () => {
    token = await accessToken(refresh);
    const { release, pages } = await newestDeployRelease(token);
    const versionName = release.version.name;
    const versionId = versionName.split('/').pop();

    // Pin the expected version when the caller named one, so a capture cannot
    // silently record a different live release than the run validated.
    if (opts.expectVersion && opts.expectVersion !== versionId) {
      fail('HOSTING_INVENTORY_VERSION_MISMATCH', `live DEPLOY is ${versionId}, expected ${opts.expectVersion}`);
    }

    const version = await apiGet(`https://firebasehosting.googleapis.com/v1beta1/${versionName}`, token);
    if (version.status && version.status !== 'FINALIZED') {
      fail('HOSTING_INVENTORY_VERSION_NOT_FINAL', `version ${versionId} is ${version.status}`);
    }
    // Completeness, against the API's own count rather than against this
    // client's view of the same list. Every earlier check summed terms derived
    // from the listing, so a short listing shrank both sides and still passed.
    // The comparison is made against the RAW paginated entries, before any
    // status filter, because fileCount counts entries.
    if (version.fileCount === undefined || version.fileCount === null) {
      fail('HOSTING_INVENTORY_FILE_COUNT_MISSING', `version ${versionId} reported no fileCount`);
    }
    const declaredCount = Number(version.fileCount);
    if (!Number.isInteger(declaredCount)) {
      fail('HOSTING_INVENTORY_FILE_COUNT_MISSING', `version ${versionId} fileCount is not an integer: ${version.fileCount}`);
    }
    const listed = await versionFiles(versionName, versionId, declaredCount, token);
    const allFiles = listed.live;
    const payloadFiles = allFiles.filter((f) => isProductionPayload(f.path));
    const generated = allFiles.filter((f) => isGenerated(f.path)).length;
    if (!allFiles.some((f) => f.path === '/manifest.json')) {
      fail('HOSTING_INVENTORY_NO_MANIFEST', `version ${versionId} has no /manifest.json`);
    }
    if (!payloadFiles.some((f) => /\.apk$/.test(f.path))) {
      fail('HOSTING_INVENTORY_NO_APK', `version ${versionId} has no /releases/*.apk`);
    }

    // Unknown paths are tolerated only if they are page chrome already tracked
    // in the repository or one of the two explicitly recognised staging OTA
    // files. A new directory is a payload region this tool does not understand,
    // and capturing it blindly could publish something unexpected.
    const unknown = allFiles.filter(
      (f) => !isGenerated(f.path) && !isProductionPayload(f.path) && !isKnownNonPayload(f.path),
    );
    if (unknown.length > 0) {
      fail('HOSTING_INVENTORY_UNEXPECTED_PATH', unknown.map((f) => f.path).join(', '));
    }

    const manifestBytes = await download(`${ORIGIN}/manifest.json`);
    const manifest = JSON.parse(manifestBytes.toString('utf8'));
    const manifestSha = sha256(manifestBytes);

    const downloadUrl = manifest.downloadUrl;
    if (typeof downloadUrl !== 'string' || !downloadUrl.startsWith(ORIGIN + '/releases/')) {
      fail('HOSTING_INVENTORY_MANIFEST_URL_FOREIGN', `downloadUrl is ${downloadUrl}`);
    }
    const manifestApkPath = new URL(downloadUrl).pathname;

    // Completeness is decided by the manifest, not by what happened to download:
    // the APK the manifest names must be in the captured set and on the API.
    const apkFile = allFiles.find((f) => f.path === manifestApkPath);
    if (!apkFile) {
      fail('HOSTING_INVENTORY_APK_NOT_IN_VERSION', `manifest names ${manifestApkPath}, which is not in ${versionId}`);
    }

    const captured = [];
    for (const file of payloadFiles) {
      // eslint-disable-next-line no-await-in-loop
      const bytes = await download(`${ORIGIN}${file.path}`);
      const digest = sha256(bytes);
      captured.push({
        path: file.path,
        bytes: bytes.length,
        sha256: digest,
        apiHash: file.hash || null,
        apiHashReproduced: apiHashMatches(bytes, file.hash),
        body: bytes,
      });
    }

    const apk = captured.find((f) => f.path === manifestApkPath);
    if (!apk) fail('HOSTING_INVENTORY_APK_NOT_IN_VERSION', `manifest names ${manifestApkPath}, which was not captured`);
    // The integrity authority. A mismatch means the file the site serves is not
    // the file the manifest tells every installed build to trust.
    if (typeof manifest.sha256 !== 'string' || manifest.sha256 !== apk.sha256) {
      fail('HOSTING_INVENTORY_APK_HASH_MISMATCH',
        `${manifestApkPath} sha256 ${apk.sha256} != manifest ${manifest.sha256}`);
    }

    const out = path.resolve(opts.output);
    // The output directory is wiped before it is rewritten, so a mistyped
    // argument (`--output .`) would delete the checkout. Only a directory this
    // tool owns is allowed to be removed.
    if (path.basename(out) !== 'recovery-baseline') {
      fail('INVENTORY_BAD_OUTPUT', `--output must name a "recovery-baseline" directory, got ${out}`);
    }
    fs.rmSync(out, { recursive: true, force: true });
    for (const file of captured) {
      const target = path.join(out, file.path.replace(/^\//, '').split('/').join(path.sep));
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, file.body);
    }

    const capturedPaths = captured.map((f) => f.path).sort();
    // Staging is classified separately from tracked page chrome: neither is
    // captured, but only one of them belongs to the staging OTA channel.
    const stagingPaths = allFiles
      .filter((f) => isStagingPayload(f.path))
      .map((f) => f.path)
      .sort();
    const uncapturedTracked = allFiles
      .filter((f) => !isGenerated(f.path) && !isProductionPayload(f.path) && !isStagingPayload(f.path))
      .map((f) => f.path)
      .sort();

    const inventory = {
      schemaVersion: 1,
      capturedAt: new Date().toISOString(),
      project: PROJECT,
      site: SITE,
      origin: ORIGIN,
      release: {
        type: release.type,
        releaseTime: release.releaseTime,
        versionName,
        versionId,
        pagesScanned: pages,
      },
      version: {
        status: version.status,
        fileCount: Number(version.fileCount),
        fileCountListed: allFiles.length,
        versionBytes: Number(version.versionBytes),
        generatedFileCount: generated,
      },
      completeness: {
        // `countMatches` was enforced against the RAW paginated listing, before
        // any status filter; it is recorded here as evidence, not re-decided.
        // `accountedFor` only says every live path was classified into a known
        // bucket, which is a bookkeeping invariant.
        declaredFileCount: declaredCount,
        listedFileCount: listed.raw.length,
        listedPages: listed.pages,
        activeFileCount: allFiles.length,
        inactivePaths: listed.inactive,
        duplicatePaths: listed.duplicates,
        countMatches: listed.raw.length === declaredCount,
        manifestReferencedApk: manifestApkPath,
        apkCaptured: capturedPaths.includes(manifestApkPath),
        payloadFileCount: payloadFiles.length,
        capturedFileCount: captured.length,
        stagingFileCount: stagingPaths.length,
        trackedNonPayloadFileCount: uncapturedTracked.length,
        accountedFor: payloadFiles.length + stagingPaths.length + uncapturedTracked.length + generated === allFiles.length,
      },
      manifest: {
        latestVersion: manifest.latestVersion,
        latestBuildNumber: manifest.latestBuildNumber,
        minimumSupportedVersion: manifest.minimumSupportedVersion,
        downloadUrl,
        sha256: manifest.sha256,
        signingCertSha256: manifest.signingCertSha256,
        fileSha256: manifestSha,
      },
      files: captured.map((f) => ({
        path: f.path,
        bytes: f.bytes,
        sha256: f.sha256,
        apiHash: f.apiHash,
        apiHashReproduced: f.apiHashReproduced,
      })),
      stagingPaths,
      uncapturedTrackedPaths: uncapturedTracked,
    };
    writeJson(path.join(out, 'inventory.json'), inventory);

    const sums = captured
      // Two spaces keeps sha256sum in text mode with no `*` marker, so the file
      // reads the same on every platform.
      .map((f) => `${f.sha256}  ${f.path.replace(/^\//, '')}`)
      .sort()
      .join('\n');
    fs.writeFileSync(path.join(out, 'SHA256SUMS'), `${sums}\n`);

    const summary = [
      `RECOVERY_INVENTORY OK version=${versionId} release=${release.releaseTime}`,
      `  apk=${manifestApkPath} (${apk.bytes} bytes, sha256 ${apk.sha256.slice(0, 12)}…) matches manifest`,
      `  captured=${captured.length} production payload file(s); staging-not-captured=${stagingPaths.length}; tracked-but-not-captured=${uncapturedTracked.length}; generated=${generated}; listed=${allFiles.length}`,
      `  output=${out}`,
    ].join('\n');
    process.stdout.write(`${summary}\n`);

    if (process.env.GITHUB_STEP_SUMMARY) {
      fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, [
        '### Production recovery baseline captured',
        `- release: \`${versionId}\` (\`${release.releaseTime}\`)`,
        `- APK: \`${manifestApkPath}\` (${apk.bytes} bytes)`,
        `- sha256: \`${apk.sha256}\` (matches the production manifest)`,
        `- files captured: ${captured.length} (production payload) + ${stagingPaths.length} staging (not captured) + ${uncapturedTracked.length} tracked + ${generated} generated = ${allFiles.length}`,
        '',
      ].join('\n'));
    }
  })().catch((err) => {
    process.stderr.write(`::error::${err.code || 'HOSTING_INVENTORY_FAILED'} ${err.message}\n`);
    process.exitCode = 1;
  }).finally(() => {
    token = null;
  });
}

// Offline path for tests and for a reviewer checking the packaging logic. It
// runs the same verification matrix against a fixture directory.
function mainFixture(opts) {
  const dir = path.resolve(opts.fixture);
  const manifestPath = path.join(dir, 'manifest.json');
  if (!fs.existsSync(manifestPath)) fail('HOSTING_INVENTORY_NO_MANIFEST', manifestPath);
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const url = new URL(manifest.downloadUrl);
  // Same rules the live path applies: a manifest may not name the rewrite, and
  // it must name an APK on this site.
  if (isReservedRewrite(url.pathname)) {
    fail('HOSTING_INVENTORY_RESERVED_PATH', `${url.pathname} is a Hosting rewrite, not a payload file`);
  }
  if (url.origin !== new URL(ORIGIN).origin || !url.pathname.startsWith('/releases/')) {
    fail('HOSTING_INVENTORY_MANIFEST_URL_FOREIGN', `downloadUrl is ${manifest.downloadUrl}`);
  }
  if (!isProductionPayload(url.pathname)) {
    fail('HOSTING_INVENTORY_APK_NOT_IN_VERSION', `${url.pathname} is not a /releases/*.apk path`);
  }
  const apkPath = path.join(dir, url.pathname.replace(/^\//, '').split('/').join(path.sep));
  if (!fs.existsSync(apkPath)) {
    fail('HOSTING_INVENTORY_APK_NOT_IN_VERSION', `manifest names ${url.pathname}, which the fixture lacks`);
  }
  const bytes = fs.readFileSync(apkPath);
  const digest = sha256(bytes);
  if (manifest.sha256 !== digest) {
    fail('HOSTING_INVENTORY_APK_HASH_MISMATCH', `${url.pathname} sha256 ${digest} != manifest ${manifest.sha256}`);
  }
  process.stdout.write(`RECOVERY_INVENTORY FIXTURE OK apk=${url.pathname} (${bytes.length} bytes)\n`);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.fixture) {
    mainFixture(opts);
    return;
  }
  if (opts.preflight) {
    // A real read, not a presence check: a non-empty token that Firebase
    // rejects must fail here rather than after the build has been signed.
    // Both scopes the capture needs are exercised. Releases-read alone would
    // pass here and then fail mid-capture, after the APK is built and signed,
    // on a token without files-read.
    const refresh = process.env.FIREBASE_TOKEN;
    await accessToken(refresh).then(async (token) => {
      const page = await apiGet(`${API}/${SITE_PATH}/releases?pageSize=100`, token);
      const count = (page.releases || []).length;
      const { release } = await newestDeployRelease(token);
      const versionName = release.version.name;
      const versionId = versionName.split('/').pop();
      // One page is enough to prove read access; the capture walks all pages.
      const { files } = await versionFilesRaw(versionName, token, { pageLimit: 1 });
      process.stdout.write(
        `HOSTING_INVENTORY PREFLIGHT OK releases_readable=${count > 0} `
        + `files_readable=true version=${versionId} files_on_first_page=${files.length}\n`,
      );
    }).catch((err) => {
      process.stderr.write(`::error::${err.code || 'HOSTING_INVENTORY_FAILED'} ${err.message}\n`);
      process.exitCode = 1;
    });
    return;
  }
  await mainCapture(opts);
}

if (require.main === module) {
  main().catch((err) => {
    process.stderr.write(`::error::${err.code || 'HOSTING_INVENTORY_FAILED'} ${err.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = {
  apiHashMatches,
  isProductionPayload,
  isStagingManifest,
  isStagingApk,
  isStagingPayload,
  isKnownNonPayload,
  sha256,
  classifyFiles,
};
