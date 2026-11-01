# SpendSense — landing page design standard

Normative for `ota/public/` (the public site at `https://spendsense-ota-2026.web.app`).
The app's own standard lives in `DESIGN.md`; this file governs the web surface only.

**Mode: Persuade.** A visitor decides in under a minute whether to install an app
that reads their SMS. There is no second page. Every element serves that decision.

---

## 1. The world: a glazier's colour-field partition

The page is a steel-framed glass wall read as an elevation.

- **Matte black bars are the only line ink.** 10px at desktop, 7px at mobile. They
  are structural, never decorative: every pane sits inside them, and the bar
  thickness is preserved when bays restack on a phone.
- **Clear and seeded panes are the ground.** `#f4f1ea` paper, `#fbfaf6` bright,
  `#e8e3d8` low. The fine speckle is a two-tone radial-gradient texture that reads
  as seeded glass — no image request.
- **Three saturated panes, reserved.** Cobalt `#1b3fa0`, amber `#c08a2e`, oxblood
  `#5e1b22`. They appear only where a visitor must act or must trust something:
  the note, the budget pane, the export pane, the primary action. Nothing else may
  borrow them.
- **Hierarchy comes from pane size and glass colour, not type weight.**

## 2. Type

| Role | Face | Use |
|---|---|---|
| Display | **Archivo** 600/700/800 | Caps headlines and pane headings. Set level inside its pane, never across a bar. |
| Prose | **Instrument Sans** 400/500/600 | Body copy. Measure capped at 68ch. |
| Measurement | **Geist Mono** 500 | Numbers, file extensions, and only those. Never as a "technical" costume. |

All three are SIL OFL 1.1, self-hosted from `/legal/fonts/`, and preloaded. The
page makes no third-party request of any kind.

**Declare font faces with longhands, never the `font:` shorthand with a
`var()`.** A shorthand whose custom property fails to resolve drops the whole
declaration, taking the size with it.

## 3. Grid

Twelve columns, `gap: var(--bar-w)`. Rows are **explicit** — `grid-row` on every
pane — because auto-placement pushed the download below the install card and, on
mobile, let the refusal band overlap the action pane. Panes that share a row must
share it by intent, never by accident.

Desktop first viewport (row 1): masthead + nav (cols 1–2) · claim (3–8) ·
cobalt note (9) · live readout (10–12) · install (10–12, second line).
Row 2: the action pane (3–9), immediately beneath the claim.

Mobile: one column, rows in reading order — masthead, claim, readout, action,
install, proofs, nav, refusal, footer.

## 4. Pane sizing

A pane is a frame for its content, not a container to be filled. Every pane sizes
to what it holds; the grid pins each to its own row so no pane floats above black.

- **No pane may float above an unfilled row.** Side-by-side panes of different
  heights used to leave black wells under the short one. Side columns now fill
  their rows; the readout fills the claim's row and its lower half carries a
  drawn scale so it reads as an instrument face, not as empty glass.
- **`min-height` on a pane is a smell.** The claim carried one and grew longer than
  its own copy. A pane's floor comes from its padding and type.
- **The note is the one exception.** It runs the height of the first two rows
  because it is a vertical accent, and its label is set along that height.
- **Verify by measurement, not by eye.** Compare `getBoundingClientRect().height`
  against the sum of children plus gaps plus padding. A difference above ~20px needs
  a reason; a drawn element, or an authored accent, is a reason.

## 5. Glass

The wall is a light cage over a colour-field. Panes are frosted glass laid over it.
Without something behind it there is nothing to refract, which is why a flat black
ground reads as matte card rather than glass.

- **Field.** Three large soft radial fields in cobalt, amber and oxblood, held far
  out of register behind the wall, over the bar colour. They are the only
  light the glass picks up.
- **Pane.** A translucent milky fill, `backdrop-filter: blur(18px) saturate(1.25)`,
  a 1px lit top edge, a 1px dark bottom edge, and one soft low-offset shadow.
- **Refused.** No glow, no gradient borders, no purple, no neon. Saturated panes
  are tinted glass (a gradient fill plus their own backdrop-filter), not painted
  slabs. Frosting denser than the field is how an unprovable claim is expressed;
  the Cloud Backup pane blurs harder and desaturates.
- **Fallback.** `@supports not (backdrop-filter)` returns every pane to its opaque
  colour, so the page never degrades to washed-out text.
- **Contrast is checked on the composite,** not on the declared colour: fill over
  field, then text over fill. Every text run measures 4.78:1 or better.

## 6. The one live element

The readout pane shows a figure counted **on the page** (SMS sent to a server: 0)
and states beside it what it measures. It settles once on load, then stops. It
honours `prefers-reduced-motion` by rendering the final value with no count.
It is the page's only motion moment; there is no other entrance animation.

## 7. Honesty rules

- A claim we cannot prove is **frosted**, never omitted: the Cloud Backup pane is
  visibly unavailable and says why. Dropping it silently would read as a hidden gap.
- No invented numbers, testimonials, ratings, user counts or press.
- No "bank-grade", "unhackable", or accuracy claims.
- The refusal band is load-bearing content, not decoration: it lists what the app
  will not do, checked against the app's permissions.

## 8. Non-negotiables

- Contrast ≥ 4.5:1 body, ≥ 3:1 large text, verified on the rendered page.
- Visible focus ring on every interactive element; a skip link to `#main`.
- `prefers-reduced-motion` removes the count, scroll smoothing and all transitions.
- No cookies, no analytics, no third-party scripts, no webfont CDN.
- **`/manifest.json` and `/releases/**` are production OTA infrastructure.** No page
  work may touch them. The catch-all rewrite to `/404.html` is safe because those
  paths exist as real files.

## 9. Static asset cache-busting

Firebase Hosting serves `landing.css` with default caching, and browsers hold it.
`index.html` appends `?v=<timestamp>` to the stylesheet URL. **Bump it on every
deploy that changes CSS**, or returning visitors get the previous layout.

---

## Provenance

| Asset | Origin |
|---|---|
| `legal/favicon.png` | App launcher icon (`assets/icons/app_icon.png`), first-party |
| `legal/social-preview.png` | Generated from the app icon, first-party |
| `fonts/*.woff2` | Archivo, Instrument Sans, Geist Mono — SIL OFL 1.1, via Fontsource CDN |
| Pane texture | CSS radial-gradients, no raster |
| All icons | Inline authored SVG, 1.7 stroke, round caps |
