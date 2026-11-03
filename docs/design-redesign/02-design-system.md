# SpendSense proposed design direction and system

**Status:** proposal for review before UI implementation.  
**Baseline:** local checkout `release/2.0.13+38` (`9b9f6bd`); the user reports OTA build `2.0.23 (build 48)`. Reconcile these versions before implementation.

## Direction

Build a calm, precise, personal finance interface that makes the period, money movement, and next useful action easy to understand. Borrow the clarity of account summaries and transaction lists, the approachable plain-language explanations of budgeting products, the careful grouping of analytics, and the restraint of a well-made system wallet. These are principles only; SpendSense's existing feature set and brand are the source of truth.

### Principles

1. **Clarity before decoration.** Use typography, alignment and spacing for hierarchy. Keep gradients, glow, blur and elevation rare and purposeful.
2. **Numbers need context.** Pair amounts with labels, currency, period and comparison basis. Format monetary values consistently and preserve tabular figures.
3. **One hierarchy across the product.** A screen title, key result, supporting explanation, grouped content and actions should use the same roles everywhere.
4. **Themes keep their identities.** Preserve every current `AppPalette` identity, persisted ID, mode behavior, and palette-independent income/expense/error semantics. Do not collapse the palette set to one brand color.
5. **Accessible by construction.** Content remains readable at large text sizes; controls are named, focusable and large enough; charts have summaries; meaning is not conveyed by hue alone.
6. **Motion explains change.** Keep meaningful state feedback and navigation continuity, honor reduced motion, and avoid perpetual or ornamental motion.
7. **Responsive to constraints.** Prefer scrollable, constraint-aware layouts and flexible columns over fixed screen assumptions. Preserve content access when the keyboard or system insets change.

## Token contract (proposed)

This establishes roles, not final numeric color values. Values must be mapped from the actual palette data only after reconciling the OTA source and reviewing representative screenshots.

### Color roles

| Role | Purpose |
|---|---|
| `canvas` | Main app background |
| `surface` / `surfaceSubtle` / `surfaceRaised` | Grouped content, selected sections, and overlays |
| `textPrimary` / `textSecondary` / `textTertiary` | Content hierarchy; tertiary is never the only source of essential meaning |
| `outline` / `divider` / `focus` | Structure, separation, and keyboard/accessibility focus |
| `accent` / `onAccent` | Primary action and selected navigation state, with a verified readable pair |
| `success`, `warning`, `error` | System status and feedback |
| `income`, `expense`, `neutralMoney` | Palette-invariant financial semantics; pair color with sign/label/icon |
| `chartSeries[]` | Distinguishable data series with labels, legend, or direct values |
| `disabled`, `pressed`, `selected` | Explicit component interaction states for every theme |

Use `ColorScheme` and existing `AppColors`/`AppPalette` accessors as the single mapping layer. Screen components should not invent their own hex values. Preserve each palette's own light and dark surfaces and avoid accent leakage when users switch themes.

### Typography roles

Keep the bundled, user-selectable type presets. Define and apply a compact shared role scale:

- `displayAmount`: prominent balance/total, tabular digits, scales and wraps safely.
- `screenTitle`: page identity.
- `sectionTitle`: grouped content heading.
- `body`: explanatory and transaction text.
- `bodyEmphasis`: merchant/title and key status.
- `label`: compact control and metadata labels.
- `caption`: supporting date/source only when it remains readable.

Review the current 10–12.5sp usage before retaining it. Avoid fixed heights around scalable text and don't silently cap user text scaling. Financial amounts must use the body face with tabular numerals even when a decorative display preset is selected.

### Spacing and geometry

Retain the existing 4dp base rhythm and simplify its roles around `4, 8, 12, 16, 24, 32` dp. Use one adaptive page gutter policy, clear section separation, and component padding proportional to hierarchy. Define a restrained radius set for controls, grouped surfaces, sheets and dialogs; reserve pill geometry for controls that are semantically pills. Avoid putting a card inside another card when spacing and a divider can express the grouping.

All primary controls target at least 48dp on Android and 44pt on iOS; the actual hit bounds can exceed the visual icon. Fixed bars and floating actions must report their real safe-area/large-text height to scroll content.

### Surfaces and elevation

- Default to flat, opaque surfaces with subtle outlines or tonal separation.
- Do not put blur, sheen, ambient glows or shadows on routine list rows.
- A single translucent treatment may remain for a contextual floating control if contrast remains stable over every scroll background and high-contrast mode has an opaque alternative.
- Use elevation to distinguish overlays and dialogs, not to imply that every data block is a separate card.
- Keep the current AMOLED option meaningful while preserving palette dark-mode behavior.

### Iconography and interaction states

Use the app's existing Material icon family consistently. Give icon-only actions accessible labels and adequate hit regions. Keep semantic state visible with more than color: selection marks, labels, signs, shapes, values, or text. Inputs have persistent labels and inline errors; loading, empty, offline and failure states say what happened and how to recover.

### Motion

Keep shared motion tokens, reduced-motion behavior and interruptible user-triggered feedback. Use short transitions for selection/press and contextual transitions for route/sheet changes. Avoid animated blur and large groups of staggered entrances; motion must not delay input or be required to understand a chart/value change.

## Navigation proposal

Keep the current five destinations and add-transaction entry point until product analytics/user research supports a structural change. Revisit the current glass pill and all-caps 10sp labels. Prefer a stable, clearly selected bottom navigation with readable labels, high-contrast opaque fallback and a 48dp target. Preserve the convenient add action without allowing it to cover the center destination. Validate whether the Activity route is discoverable enough from Home/Insights and keep its entry points explicit.

## Responsive and accessibility requirements

- Verify compact 320–360dp widths, a common 375–430dp phone, landscape, and a larger/tablet width. For wider layouts, constrain reading measure and use extra width for side-by-side related content, not stretched rows.
- Support system text scaling and the largest available setting without clipping, truncating amounts, hiding actions, or overflowing sheets.
- Verify light/dark and every palette with computed text contrast (4.5:1 for normal text, 3:1 for large text/non-text controls where applicable) and visible focus.
- Verify TalkBack and VoiceOver reading order, labels, selected states, form errors, announcements, modal focus, and chart summaries.
- Make income/expense and chart categories understandable in grayscale and without color perception.
- Verify keyboard/safe-area handling for authentication, amount entry, filters and plan editors.
- Verify reduced-motion and high-contrast settings.
- Use Flutter's Accessibility Guideline API alongside focused widget tests for target size, labels and contrast. Then inspect real-device behavior.

## Incremental implementation plan

1. **Baseline alignment:** compare local source against mobile OTA `2.0.23 (build 48)` and review the actual installed screens. No UI work proceeds from an outdated baseline by assumption.
2. **Foundation:** map existing theme identities into agreed semantic roles; standardize text, spacing, radius, surfaces, buttons, rows, sheets and navigation states.
3. **Core scan path:** Home and bottom navigation, then Activity and Add Transaction. Preserve providers, calculations, routes, SMS access and ledger operations.
4. **Planning and analysis:** Budgets, Bills, Recurring, Insights, Cards/Payment Instruments and Summary/Export.
5. **Account and secondary flows:** Settings, Appearance/Typography, Sound, Assistant/Privacy/AI settings, Authentication, Update and Launch.
6. **Validation per stage:** run narrow existing tests for changed behavior, widget tests at constrained widths and large text, accessibility checks, theme checks and a device review. Add tests only where an acceptance gap exists.

No visual implementation should begin until the source/build mismatch and this direction are reconciled.

