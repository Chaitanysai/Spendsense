# Design research

Reference screens and pattern notes for the SpendSense home redesign.

- [Home redesign — GO Club × Suno](./home-redesign.md): brief, reference
  patterns, screen specification, implementation map, verification.
- [home-dark.png](./home-dark.png) / [home-light.png](./home-light.png):
  deterministic 390 × 844 previews rendered from the real widgets with the
  bundled fonts. Regenerate with
  `flutter test --no-pub tool/home_preview_test.dart`.
- `device-*.png`: real OnePlus 7T screenshots from the separate
  `com.example.spendsense.preview` package — home, privacy, sections, recent,
  add sheet and edit mode. See the device section of the redesign document.
- [palette-system.md](./palette-system.md): the four 2026 premium palettes,
  token mapping, invariants, and the 19-screen × 4-palette × 2-theme sweep.
- `palette-gallery/`: contact sheets of every screen in every premium palette,
  light and dark.

Appllama skills used: `appllama-usage` and `appllama-app-design-skill` from
<https://github.com/Appllama/appllama-skills>. The Appllama MCP
(`https://mcp.appllama.io/mcp`) requires a Pro account token; see the document
for what was studied from public evidence instead.
