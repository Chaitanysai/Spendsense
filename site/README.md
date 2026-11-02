# SpendSense — home introduction site

The public introduction page at `https://spendsense-ota-2026.web.app/`.

**Mode: Persuade.** A visitor decides in under a minute whether to install an
Android app that reads their SMS. Every section serves that decision.

---

## 1. Where this lives, and what it must not break

The landing page shares an origin with the OTA channel that installed builds poll
for self-update. `firebase deploy` replaces the **whole** Hosting release, so the
published site is exactly the contents of `ota/public` at deploy time. Anything
missing from that directory disappears from production.

A previous deploy did exactly that and removed the live `manifest.json`, breaking
updates for every installed build. The topology below exists to make that class of
mistake impossible to repeat.

```
site/                        source (React + Vite + TypeScript + Three.js)
  src/                       app
  vite.config.ts             build topology
  scripts/clean.mjs          clears only ota/public/site/assets
  scripts/guard.mjs          asserts the OTA payload survived the build
  dist/                      ignored

ota/public/                  the deployed hosting root
  index.html                 app shell               ← written by the build
  site/assets/*              hashed JS/CSS           ← written by the build
  manifest.json              OTA contract            ← never written by the build
  releases/*.apk             OTA payload             ← never written by the build
  legal/**                   legal pages             ← never written by the build
  landing.css, 404.html      retained; asserted by CI
```

Two independent guards:

1. **`emptyOutDir: false`** for `ota/public`, with `scripts/clean.mjs` removing
   only `ota/public/site/assets`. A build cannot delete anything it does not own.
2. **`scripts/guard.mjs`** runs after every build and fails it unless
   `manifest.json`, the APK named in it (digest matched), `index.html`,
   `404.html`, `landing.css` and the legal pages are all still present.

Build: `cd site && npm install && npm run build`.

---

## 2. The design language

The reference for this page is Moorline (Vite + React + Three.js; a 15s loop in
which a particle sphere grows into a tree standing in dark rippling water, then
folds into a rotating particle cube). What was taken is the **language**, not the
artwork:

| Taken | Not taken |
|---|---|
| Near-black ground (`#01040a`) with one WebGL particle centrepiece | The tree, the cube, the fictional-insurance framing |
| Count-up preloader | Moorline's logo, copy, or assets |
| Centred pill navigation over the hero | Its blue/cyan palette |
| Very large tightly-tracked display type | Its pixel font file (not bundled, not hotlinked) |
| Full-bleed hero with the form behind the copy | Its section order |
| Numbered glass cards (`01`–`06`) | — |
| Scroll-driven form transformation | — |

**Colour is SpendSense's.** Electric green `#22e07a` for action, teal `#1fd1c4`
for light. The app's own palettes are dark navy glass, and the app's type is
Poppins / Space Grotesk / Geist / Inter, so a dark glass surface with a green
accent is continuous with the product rather than a separate brand.

### The centrepiece

A drifting constellation of transaction nodes that resolves into an ordered
ledger lattice, standing in rippling water with its reflection beneath. It is the
same rendering discipline as the reference (one `Points` cloud, a custom shader, a
mirrored reflection, cursor repulsion) with geometry that means something here:
individual payments gathering into one readable record.

It is original: no copied shaders, geometry, or assets.

Cost control:

- one geometry, one draw call for the cloud, one for the reflection, one quad for
  the water
- density 14,000 desktop / 5,200 below 760px
- DPR capped at 2 desktop, 1.5 mobile
- the loop stops when the canvas leaves the viewport or the tab is hidden
- no per-frame allocation

---

## 3. Type

| Role | Face | Note |
|---|---|---|
| Display | Geist Mono 500, uppercase, `-0.045em` | Carries the reference's bitmap character without a third-party font request |
| UI and prose | Instrument Sans 400/500/600 | |
| Measurements | Geist Mono 500 | Values, numbers, kickers |

All faces are self-hosted under `/legal/fonts/`. The page makes **no third-party
request** of any kind: no font CDN, no analytics, no ad network.

> The shared `/legal/fonts/fonts.css` has a stray `fonts/` prefix on every `src`
> except `archivo-400`, so it only resolves when loaded from `/legal/`. The site
> therefore declares its own `@font-face` rules against absolute paths in
> `src/fonts.css` rather than reusing that file.

---

## 4. Sections

1. **Hero** — eyebrow, display headline, supporting copy, two CTAs, particle form.
2. **Product** — the mechanism, with an illustrative parsed-transaction specimen
   labelled as such.
3. **Features** — six numbered glass cards.
4. **How it works** — four steps on a scroll-scrubbed rail.
5. **Privacy** — three claims plus a refusal list.
6. **Install** — final CTA.
7. **Footer** — product, legal, source.

### Honesty rules

Every claim is checkable in the app. Specifically excluded, per `PRODUCT.md`:

- no user counts, ratings, testimonials, or press mentions
- no "bank-grade", "military-grade", "unhackable"
- no claim of automatic categorisation accuracy
- no claim that SpendSense is a budgeting adviser
- **no claim that data is backed up** — it is not, and the page says so

The specimen card carries "Illustrative example, not a customer record."

---

## 5. Motion

One authored entrance per section; no scattered effects.

| Element | Behaviour |
|---|---|
| Preloader | counts to 100, ~1.15s, then fades |
| Hero | particle cloud fades up and resolves from scatter toward lattice |
| Scroll | hero progress feeds the resolve; the form orders itself as the page moves |
| Cursor | pointer repulsion in the cloud, eased, mouse only, one rAF per move |
| Reveals | `IntersectionObserver`, fires once, then disconnects |
| How it works | scroll-scrubbed rail; a single state write per step change |
| Hover | 1px lift on buttons, border and fill change on cards |

`prefers-reduced-motion: reduce` disables the preloader, the WebGL scene (a static
CSS orb and horizon replace it), all reveals, and every transition.

**Reveal is progressive enhancement.** Elements are visible by default; the
stylesheet only hides them once `html.js-reveal` is set by a hook that has already
confirmed `IntersectionObserver` exists. A failure leaves the page readable rather
than blank.

---

## 6. Accessibility

- Skip link to `#main`.
- Focus ring: 2px green at 3px offset on every interactive element.
- Mobile menu: `aria-expanded`, `aria-controls`, Escape to close, labelled button.
- The WebGL canvas is `aria-hidden`; it carries no meaning unavailable as text.
- Contrast measured on the **composited** result (glass over ground): 5.05 to
  10.73:1 across body, links, captions and labels. All pass AA.
- Nothing depends on hover to be understood.

---

## 7. Verification

Run and passing:

| Check | Command | Result |
|---|---|---|
| Typecheck | `npm run typecheck` | pass |
| Lint | `npm run lint` | pass, 0 warnings |
| Build | `npm run build` | pass |
| OTA guard | (runs inside build) | manifest, APK digest, legal pages intact |
| Browser | Playwright, 1440 / 1024 / 390 | 0 console errors, 0 overflow |

Bundle: 54.7 kB gzip app + 116.5 kB gzip three, split into two chunks so Three.js
does not block first paint.
