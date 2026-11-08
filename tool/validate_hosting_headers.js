// Fails loudly if firebase.json's Hosting cache policy stops being what the
// deploy relies on.
//
//   node tool/validate_hosting_headers.js
//
// Why this exists rather than a live check: Firebase Hosting's own emulator
// (firebase-tools 15.x) does not apply `hosting.headers` at all, so no local
// server can prove the policy. The rules below are therefore evaluated exactly
// the way Hosting documents and ships them:
//
//   * matching is done on the REQUEST path, BEFORE rewrites are applied
//   * every matching rule is applied in the order defined
//   * for a repeated key the LAST matching rule wins (superstatic's headers
//     middleware pushes each match through res.setHeader)
//   * patterns are globs anchored at the root, matched like minimatch
//
// The expected policy, and the evidence behind it, is in
// docs/hosting-cache-headers.md.

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const HOSTING_ROOT = path.join(ROOT, 'ota', 'public');

const IMMUTABLE = 'public, max-age=31536000, immutable';
const REVALIDATE = 'no-cache, max-age=0, must-revalidate';
const NO_STORE = 'no-store, max-age=0, must-revalidate';

const failures = [];
const fail = (message) => failures.push(message);

// --- glob matching, minimatch-compatible for the patterns used here ----------

/**
 * Translates a Hosting glob into an anchored RegExp.
 *
 * `**` spans path separators, `*` does not, and `**\/` may match zero
 * segments (so `**\/*.html` matches `/index.html`, not just nested files).
 * `@(a|b)` is the extglob form Hosting documents for extension lists.
 */
function globToRegExp(glob) {
  let out = '';
  for (let i = 0; i < glob.length; i += 1) {
    const c = glob[i];
    if (c === '*') {
      if (glob[i + 1] === '*') {
        // "**/" => zero or more whole segments; "**" at the end => anything.
        if (glob[i + 2] === '/') {
          out += '(?:.*/)?';
          i += 2;
        } else {
          out += '.*';
          i += 1;
        }
      } else {
        out += '[^/]*';
      }
    } else if (c === '?') {
      out += '[^/]';
    } else if (c === '@' && glob[i + 1] === '(') {
      const close = glob.indexOf(')', i);
      if (close === -1) {
        fail(`unparseable extglob in source ${JSON.stringify(glob)}`);
        return null;
      }
      const body = glob
        .slice(i + 2, close)
        .split('|')
        .map((alt) => alt.replace(/[.+^${}()|[\]\\]/g, '\\$&'))
        .join('|');
      out += `(?:${body})`;
      i = close;
    } else {
      out += c.replace(/[.+^${}()|[\]\\?]/g, '\\$&');
    }
  }
  return new RegExp(`^${out}$`);
}

/** Hosting normalises both the request path and the pattern to a leading "/". */
const slasher = (p) => (p.startsWith('/') ? p : `/${p}`);

// --- the configuration under test ------------------------------------------

const config = JSON.parse(fs.readFileSync(path.join(ROOT, 'firebase.json'), 'utf8'));
const hosting = config.hosting || {};

if (!Array.isArray(hosting.headers)) {
  fail('firebase.json has no hosting.headers array');
}

const rules = (hosting.headers || []).map((rule, index) => {
  if (typeof rule.source !== 'string' && typeof rule.regex !== 'string') {
    fail(`hosting.headers[${index}] has neither "source" nor "regex"`);
  }
  return {
    index,
    source: rule.source,
    regex: rule.regex ? new RegExp(rule.regex, 'u') : null,
    test: rule.regex
      ? (target) => new RegExp(rule.regex, 'u').test(target)
      : ((re) => (target) => re !== null && re.test(target))(
          typeof rule.source === 'string' ? globToRegExp(slasher(rule.source)) : null,
        ),
    headers: Array.isArray(rule.headers) ? rule.headers : [],
  };
});

/** Final header map for a request path, applying rules in order, last wins. */
function resolveHeaders(requestPath) {
  const target = slasher(requestPath);
  const resolved = new Map();
  for (const rule of rules) {
    if (!rule.test(target)) continue;
    for (const header of rule.headers) {
      if (!header || typeof header.key !== 'string') {
        fail(`hosting.headers[${rule.index}] has a header without a key`);
        continue;
      }
      resolved.set(header.key.toLowerCase(), header.value);
    }
  }
  return resolved;
}

// --- required policies ------------------------------------------------------

// undefined means "no rule sets Cache-Control", i.e. Hosting's own default of
// `max-age=3600`. Those files are not content-hashed, so they keep the default.
const MATRIX = [
  ['/', REVALIDATE],
  ['/index.html', REVALIDATE],
  ['/404.html', REVALIDATE],
  ['/legal/', REVALIDATE],
  ['/legal/index.html', REVALIDATE],
  ['/site/assets/index-It2n_Ezl.js', IMMUTABLE],
  ['/site/assets/index-vIX1ZQhS.css', IMMUTABLE],
  ['/site/assets/three-BLc3E22_.js', IMMUTABLE],
  ['/manifest.json', REVALIDATE],
  ['/releases/latest.apk', NO_STORE],
  ['/releases/spendsense-2.0.24+49.apk', IMMUTABLE],
  ['/landing.css', undefined],
  ['/legal/style.css', undefined],
  ['/legal/favicon.png', undefined],
  ['/legal/social-preview.png', undefined],
  ['/legal/fonts/instrument-sans-400.woff2', undefined],
];

const table = [];
for (const [requestPath, expected] of MATRIX) {
  const actual = resolveHeaders(requestPath).get('cache-control');
  table.push({ requestPath, expected, actual });
  if (actual !== expected) {
    fail(
      `Cache-Control for ${requestPath} is ${JSON.stringify(actual)}, expected ` +
        `${JSON.stringify(expected)}${expected === undefined ? ' (no rule: Hosting default)' : ''}`,
    );
  }
}

// --- structural invariants --------------------------------------------------

// Long-lived immutable caching is only safe where the URL changes when the
// bytes change. That is the Vite build's hashed bundle directory and the
// version-named release APKs. Anything else must not claim immutability.
const IMMUTABLE_SOURCES = new Set(['/site/assets/**', '/releases/spendsense*.apk']);
for (const rule of rules) {
  for (const header of rule.headers) {
    if (header.key.toLowerCase() !== 'cache-control') continue;
    const isImmutable = /\bimmutable\b/.test(String(header.value));
    if (isImmutable && !IMMUTABLE_SOURCES.has(rule.source)) {
      fail(`source ${JSON.stringify(rule.source)} grants immutable caching; only ${[...IMMUTABLE_SOURCES].join(', ')} may`);
    }
  }
}

// The catch-all rule exists for security headers and must stay Cache-Control
// free: it also matches rewritten Function responses (/releases/latest.apk) and
// would otherwise override the no-store the download redirect sets itself.
const catchAll = rules.filter((rule) => rule.source === '**');
if (catchAll.length !== 1) {
  fail(`expected exactly one "**" header rule, found ${catchAll.length}`);
}
for (const rule of catchAll) {
  for (const header of rule.headers) {
    if (header.key.toLowerCase() === 'cache-control') {
      fail('the "**" header rule sets Cache-Control; it would override Function responses');
    }
  }
}

// An unknown path must not be rewritten onto a cacheable 200. A catch-all
// rewrite to /404.html turns a missing hashed bundle into a 200 HTML body under
// a URL that the /site/assets/** rule tells the browser to keep for a year, so
// Hosting's native 404 (correct status, 404.html body) is required instead.
for (const rewrite of hosting.rewrites || []) {
  if (rewrite.source === '**') {
    fail('firebase.json has a catch-all rewrite; missing assets would return HTTP 200 instead of 404');
  }
}

// The no-store rule above is only meaningful while /releases/latest.apk is a
// rewrite to the download Function. A deploy without the Function serves the
// 404 page there instead.
const downloadRewrite = (hosting.rewrites || []).some(
  (rewrite) =>
    rewrite.source === '/releases/latest.apk' &&
    rewrite.function &&
    rewrite.function.functionId === 'downloadApk',
);
if (!downloadRewrite) {
  fail('firebase.json no longer rewrites /releases/latest.apk to the downloadApk function');
}

// Security headers are not part of the cache policy, but they must not be
// dropped by a cache rule inserted ahead of them.
for (const [requestPath] of MATRIX) {
  const resolved = resolveHeaders(requestPath);
  if (resolved.get('x-content-type-options') !== 'nosniff') {
    fail(`X-Content-Type-Options is missing for ${requestPath}`);
  }
  if (!resolved.get('strict-transport-security')) {
    fail(`Strict-Transport-Security is missing for ${requestPath}`);
  }
}

// --- the payload those rules describe --------------------------------------

// Immutable caching is only correct if the assets really are content-hashed.
// A build that emits an unhashed name into this directory would be cached for a
// year and never updated.
const assetsDir = path.join(HOSTING_ROOT, 'site', 'assets');
if (fs.existsSync(assetsDir)) {
  for (const name of fs.readdirSync(assetsDir)) {
    if (!/[-.][A-Za-z0-9_-]{8,}\.(?:js|css)$/.test(name)) {
      fail(`ota/public/site/assets/${name} has no content hash; immutable caching would strand it`);
    }
    if (resolveHeaders(`/site/assets/${name}`).get('cache-control') !== IMMUTABLE) {
      fail(`/site/assets/${name} is not covered by the immutable rule`);
    }
  }
}

// Every bundle the shell asks for must exist, otherwise the browser requests a
// missing hashed URL and receives the 404 page.
const shellPath = path.join(HOSTING_ROOT, 'index.html');
if (fs.existsSync(shellPath)) {
  const html = fs.readFileSync(shellPath, 'utf8');
  const referenced = new Set();
  for (const match of html.matchAll(/(?:src|href)="(\/site\/assets\/[^"]+)"/g)) {
    referenced.add(match[1]);
  }
  if (referenced.size === 0) {
    fail('ota/public/index.html references no /site/assets/ bundles');
  }
  for (const ref of referenced) {
    if (!fs.existsSync(path.join(HOSTING_ROOT, ref.replace(/^\//, '')))) {
      fail(`ota/public/index.html references ${ref}, which is missing from the payload`);
    }
  }
}

// --- report -----------------------------------------------------------------

const width = Math.max(...table.map((row) => row.requestPath.length));
for (const { requestPath, actual } of table) {
  const shown = actual === undefined ? '<none: Hosting default max-age=3600>' : actual;
  console.log(`${requestPath.padEnd(width)}  ${shown}`);
}

if (failures.length) {
  console.error(`\nHosting cache configuration is not safe to deploy:`);
  for (const message of failures) console.error(`- ${message}`);
  process.exit(1);
}

console.log('\nOK: hosting cache policy matches the deploy contract.');
