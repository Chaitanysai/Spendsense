# 2.0.26+51

UI polish carried onto the 2.0.25+50 release tree, plus an isolated staging OTA
channel and a version pre-flight.

## Interface

- **Semantic radius scale.** `AppRadius` gains named roles — `icon`, `tile`,
  `panel`, `container` — alongside the raw steps, and a `nested(outer, gap)`
  helper for the corner of a surface sitting inside another. `card` (16) and
  `plate` (10) keep their existing values; nothing in the scale moves.
- **Icon plates follow the scale.** The assistant, insights and card icon
  containers use the semantic tokens instead of their own numeric radii, so the
  plates on a screen agree with the surfaces they sit on.
- **`IconWell` carries a plate.** The icon container gains `borderRadius`,
  `size`, `glyphSize`, `plateColor` and `circular`, so an icon plate no longer
  needs a bespoke `Container`. Its default radius is now the icon-plate token
  (10) rather than the small step (8) — a 2dp change at the four existing call
  sites, and the reason the container now reads as a plate rather than a chip.
- **Assistant bubble tails** use the small step instead of a bare `4`.
- **Drag ghost.** The lifted Home row's shadow follows the `GlassCard` corner
  rather than a radius of its own, so the shadow no longer implies a shape the
  card does not have.

The assistant's AppBar mark keeps its hero gradient. It is the one plate in the
app painted with `AppColors.accentHeroGradient`, and `IconWell`'s flat wash
would have replaced it.

## Updates

- **Staging channel.** `ota-publish` takes a `channel` input. Staging publishes
  to `/staging/` and is compiled against `/staging/manifest.json`, so a staging
  build can never be offered to a production install. Production paths,
  certificate pinning and signing checks are unchanged.
- **Version pre-flight.** The workflow now refuses a candidate that is not
  strictly newer than the manifest already live on its channel. Previously such
  a build published cleanly and was then silently never offered, because the
  comparison happens on the client and nothing server-side checked it.
- **Cache rules** cover the staging paths: its manifest revalidates, its
  version-named APKs stay immutable.

`docs/OTA_RELEASE_WORKFLOW.md` has the operational path, including how a staging
build is promoted to production.

## Version

`2.0.26+51`. An update is offered to installs running `2.0.25+50` or older.

Note that `/staging/` is a public path in the hosted site: anyone with the URL
can read the staging manifest and download staging builds. It is a test channel,
not a private one.
