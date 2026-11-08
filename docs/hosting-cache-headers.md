# Hosting cache headers (P1.2)

What `firebase.json` lets a browser and the Firebase CDN keep, why, and the
evidence behind each rule. Scope: **hosting cache headers only** — no application
code, no Three.js, no RUM, no Firestore, no themes.

The hosting root is `ota/public`, published on every OTA release by
`.github/workflows/ota-publish.yml`. It serves five different kinds of thing from
one origin, and they need five different cache policies:

| What | Example path | Changes on | Correct policy |
|---|---|---|---|
| Landing shell + legal pages | `/`, `/index.html`, `/legal/` | every deploy | revalidate |
| Content-hashed bundles | `/site/assets/index-It2n_Ezl.js` | never (new name instead) | immutable |
| OTA contract | `/manifest.json` | every release | revalidate |
| Download redirect | `/releases/latest.apk` (Function rewrite) | never (points at the newest APK) | no-store |
| Version-named APK | `/releases/spendsense-2.0.24+49.apk` | never | immutable |
| Non-hashed static | `/landing.css`, `/legal/fonts/*.woff2` | in place | Hosting default (`max-age=3600`) |

## 1. Before

Measured against production, `https://spendsense-ota-2026.web.app`, before this
change:

| Request | Status | `Cache-Control` |
|---|---|---|
| `/` | 200 | `max-age=3600` |
| `/site/assets/index-It2n_Ezl.js` | 200 | `max-age=3600` |
| `/legal/` | 200 | `max-age=3600` |
| `/legal/fonts/instrument-sans-400.woff2` | 200 | `max-age=3600` |
| `/manifest.json` | 200 | `no-cache, max-age=0, must-revalidate` |
| `/releases/latest.apk` | 302 | `no-store, max-age=0, must-revalidate` |
| `/site/assets/index-OLDHASH123.js` (not in the payload) | **200** | `max-age=3600` |
| `/does-not-exist` | **200** | `max-age=3600` |

Two defects, both visible in that table:

1. **Nothing was immutable.** Every hashed bundle was re-fetched after an hour,
   so returning visitors paid full transfer cost for files whose names had
   already changed.
2. **HTML was cached for an hour next to nothing else being cached.** Once
   bundles became immutable, that asymmetry would have been the actual bug: a
   browser holding an hour-old `index.html` asks for bundles that no longer
   exist on the origin.

The last two rows are the stale-HTML/404 scenario. The cause was the catch-all
rewrite in `firebase.json`:

```json
{ "source": "**", "destination": "/404.html" }
```

Hosting rewrites do not change the status code, so every miss — including a
missing hashed bundle — was answered `200` with the 404 page as the body.

## 2. After

Header decisions resolved from the new `firebase.json` with the matcher
`firebase-tools` ships (see §4):

| Request | `Cache-Control` |
|---|---|
| `/` | `no-cache, max-age=0, must-revalidate` |
| `/index.html` | `no-cache, max-age=0, must-revalidate` |
| `/404.html` | `no-cache, max-age=0, must-revalidate` |
| `/legal/` | `no-cache, max-age=0, must-revalidate` |
| `/legal/index.html` | `no-cache, max-age=0, must-revalidate` |
| `/site/assets/*.js`, `/site/assets/*.css` | `public, max-age=31536000, immutable` |
| `/manifest.json` | `no-cache, max-age=0, must-revalidate` |
| `/releases/latest.apk` | `no-store, max-age=0, must-revalidate` |
| `/releases/spendsense*.apk` | `public, max-age=31536000, immutable` |
| `/landing.css`, `/legal/style.css`, `/legal/**` fonts and images | *(no rule)* Hosting default `max-age=3600` |

### 2.1 Measured on the live origin

Deployed on 2026-11-08 with OTA run 42514904872 (build 2.0.24+49). Readings taken
from `https://spendsense-ota-2026.web.app` after the deploy; the "before" column
is the same paths on the previous release.

| Request | Before | After (measured) |
|---|---|---|
| `/` | `max-age=3600` | `no-cache, max-age=0, must-revalidate` |
| `/index.html` | `max-age=3600` | `no-cache, max-age=0, must-revalidate` |
| `/legal/` | `max-age=3600` | `no-cache, max-age=0, must-revalidate` |
| `/manifest.json` | `no-cache, max-age=0, must-revalidate` | unchanged |
| `/releases/latest.apk` | `no-store, max-age=0, must-revalidate` | unchanged (302 to the current APK) |
| `/site/assets/index-It2n_Ezl.js` | `max-age=3600` | `public, max-age=31536000, immutable` |
| `/site/assets/index-vIX1ZQhS.css` | `max-age=3600` | `public, max-age=31536000, immutable` |
| `/site/assets/three-BLc3E22_.js` | `max-age=3600` | `public, max-age=31536000, immutable` |
| `/releases/spendsense-2.0.24+49.apk` | `max-age=3600` | `public, max-age=31536000, immutable` |
| `/site/assets/index-OLDHASH0000.js` (not in the payload) | **`200`**, `max-age=3600` | **`404`**, `no-cache, max-age=0, must-revalidate` |
| `/does-not-exist-xyz` | **`200`**, `max-age=3600` | **`404`**, `no-cache, max-age=0, must-revalidate` |

The last two rows are the stale-reference fix, confirmed live: a missing hashed
bundle now answers a real `404` and is not cached, instead of a `200` HTML body
that the immutable rule would have pinned for a year.

Four changes, in the order they matter:

1. **`/site/assets/**` is immutable.** These are Vite's content-hashed outputs
   (`index-It2n_Ezl.js`); a new build produces a new name, so a year-long cache
   can never serve stale code. `immutable` suppresses the conditional
   revalidation a browser would otherwise still send.
2. **Every HTML entry point revalidates.** `**/*.html` plus the three paths that
   serve a document without a `.html` suffix (`/`, `/legal/`, and Hosting's
   trailing-slash redirect target). `no-cache` keeps the response storable but
   forces an `ETag` revalidation, so a deploy is picked up on the next request
   and a 304 costs no body bytes.
3. **The catch-all rewrite is gone.** `404.html` is Hosting's own custom 404
   page: without the rewrite, a miss returns the same page with a **404** status.
   This is required for correctness, not tidiness — with the rewrite in place, a
   request for a hashed bundle that a deploy removed would return `200` plus the
   404 page under the `/site/assets/**` rule, and the browser would keep that
   HTML body as JavaScript for a year. Nothing on the site depends on the
   fallback: there is no client-side router (`site/src` has no router, and every
   link is `/legal/`, `/legal/#anchor` or `/releases/latest.apk`), and `/legal`
   has always been served by Hosting's own trailing-slash `301`.
4. **Deny-by-default is preserved:** `manifest.json`, `latest.apk` and the
   `**` security-header rule are unchanged, and the `**` rule still sets no
   `Cache-Control` — that is what lets the download Function keep its own
   `no-store` on a rewritten response.

`/landing.css`, the legal stylesheet, fonts and images are deliberately left on
Hosting's default. They are not content-hashed, so a long cache would strand
them after a deploy.

## 3. What was verified

### 3.1 The header decisions match the matcher Firebase ships

Firebase Hosting's emulator (`firebase-tools` 15.34.1) **does not apply
`hosting.headers` at all** — recorded here so nobody re-derives it: a minimal
project with a `/assets/**` rule and a `**` rule returns neither
`Cache-Control` nor a custom header from `firebase.emulators:start --only
hosting`. Header policy therefore cannot be verified by running the emulator.

Instead, decisions were resolved with the code `firebase-tools` uses for this
(`superstatic/lib/utils/patterns.configMatcher` + the ordered
`res.setHeader` application from `superstatic/lib/middleware/headers.js`), and
`tool/validate_hosting_headers.js` re-implements the same glob semantics with no
dependencies. The two agree on **9 patterns × 25 paths = 225 combinations**,
including edge cases (`/site/assets` without a file, `/manifest.json.bak`,
`/index.htm`, nested paths):

```
OK: matcher agrees with firebase-tools on 9 patterns x 25 paths
```

### 3.2 The configuration test catches regressions

`tool/validate_hosting_headers.js` exits non-zero on a policy that the deploy
cannot survive. Four deliberate regressions were introduced and reverted:

| Mutation | Caught |
|---|---|
| Add `Cache-Control: max-age=3600` to the `**` rule | `the "**" header rule sets Cache-Control; it would override Function responses` |
| Restore the catch-all rewrite to `/404.html` | `firebase.json has a catch-all rewrite; missing assets would return HTTP 200 instead of 404` |
| Downgrade `/site/assets/**` to `max-age=3600` | `Cache-Control for /site/assets/… is "public, max-age=3600", expected "…immutable"` |
| Delete the `/manifest.json` no-cache rule | `Cache-Control for /manifest.json is undefined, expected "no-cache…"` |

The test also asserts that the assets it grants immutability to really carry a
content hash, that every bundle referenced by `ota/public/index.html` exists in
the payload, and that the security headers still reach every path in the matrix.
It runs in `pr-build.yml`, `release-branch-ci.yml` and — as the last gate before
publish — in `ota-publish.yml`.

### 3.3 Routing, including the stale-HTML/404 scenario

With the new `firebase.json` served by the Hosting emulator (`--only hosting`):

| Request | Status | Body |
|---|---|---|
| `/` | 200 | landing shell, 2,600 B |
| `/index.html` | 200 | landing shell |
| `/legal/` | 200 | legal page, 19,856 B |
| `/legal` | 301 → `/legal/` | — |
| `/legal/index.html` | 200 | legal page |
| `/404.html` | 404 | 404 page |
| `/does-not-exist` | **404** | 404 page |
| `/site/assets/index-It2n_Ezl.js` | 200 | bundle, 171,295 B |
| `/site/assets/index-vIX1ZQhS.css` | 200 | stylesheet, 23,428 B |
| `/site/assets/index-OLDHASH0000.js` (stale name) | **404** | 404 page |

The last row is the deployment scenario that matters: a client that somehow still
holds an old `index.html` and asks for a bundle this release no longer ships now
gets a `404`, not a `200` HTML body. With the HTML revalidating on every request,
that stale state also heals on the next reload instead of persisting for an hour.

The emulator does not apply rewrites to Functions, so `/releases/latest.apk` was
verified against production instead (§1) and its rule is unchanged.

### 3.4 Known limits of this verification

- **Post-deploy header values are measured.** The policy was published on
  2026-11-08 (OTA run 42514904872, build 2.0.24+49) and every row in §2 except
  the emulator-only routing checks now matches the live origin. §2.1 records the
  before/after readings.
- A request for a *missing* hashed name does **not** inherit the
  `/site/assets/**` header in production. Measured on the live origin, a stale
  hashed URL answers `404` with `no-cache, max-age=0, must-revalidate`, so it is
  not cached for a year. This is safer than the original analysis assumed —
  Hosting's own 404 response carries its own `Cache-Control` — but the
  catch-all rewrite still had to go and stays gone: with it in place the same
  request returned `200` plus the 404 page, which no header could make safe.
- `/releases/spendsense*.apk` is a glob over version-named files. It is correct
  while the workflow names APKs `spendsense-<version>+<build>.apk`, which
  `ota-publish.yml` asserts separately.

## 4. Reproducing

```bash
# 1. The policy gate (no dependencies, runs in CI)
node tool/validate_hosting_headers.js

# 2. Routing, via the Hosting emulator
firebase emulators:start --only hosting --project demo-spendsense
curl -sI http://127.0.0.1:5000/site/assets/index-OLDHASH0000.js   # expect 404

# 3. Live values (after a deploy; safe to re-run)
for p in / /index.html /legal/ /manifest.json /site/assets/index-OLDHASH.js; do
  printf '%-34s ' "$p"
  curl -s -o /dev/null -D - "https://spendsense-ota-2026.web.app$p" |
    grep -iE '^(HTTP|cache-control)' | tr -d '\r' | paste -sd' '
done
```
