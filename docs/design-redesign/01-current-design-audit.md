# SpendSense current design audit

**Review scope:** local checkout `release/2.0.13+38`, HEAD `9b9f6bd`  
**Version discrepancy:** local `pubspec.yaml` says `2.0.13+38`; the user reports the mobile OTA build is `2.0.23 (build 48)`. This report describes only the local source snapshot and must be reconciled with build 48 before implementation.  
**Review type:** source and test inventory. Flutter/Dart are not available on this shell's PATH, so this review does not claim emulator, device, screen-reader, or visual screenshot verification.

## Summary

SpendSense already has a substantive design foundation and mature product flows. It is not a blank-slate UI: it has semantic color helpers, eleven named palettes, light/dark/system mode, configurable typography, shared spacing and motion tokens, reusable transaction and budget components, reduced-motion handling, accessibility semantics, and a broad widget-test suite.

The primary design opportunity is to reduce the number of simultaneous visual treatments and make the hierarchy more editorial and information-led. Gradient hero surfaces, ambient washes, glass cards, blur, shadows, very rounded geometry, and multiple decorative accents are all present as first-class patterns. Their cumulative use can make unrelated content compete for attention and make it harder to scan financial information. This is a directional concern from source; a device review is required to assess the actual rendered severity.

## Existing strengths

- A shared theme is built in `main.dart` from `ColorScheme.fromSeed`, and the appearance provider resolves palette, brightness, and type choices.
- `AppColors` provides theme-aware semantic accessors. `AppPalette` documents palette-invariant income and expense meaning and includes contrast-aware brand fills.
- Twelve palette identities are present: Emerald, Ocean Blue, Warm Amber, Forest Green, Royal Purple, Rose, Teal, Soft Pastel Teal, Deep Navy, Premium Blue, Plum & Blush, and Midnight. The redesign must preserve the complete set and stored palette IDs.
- `AppSpacing`, `AppRadius`, and `AppMotion` provide reusable scales; motion helpers honor the OS reduced-motion setting.
- Monetary text uses tabular figures; typography families are bundled offline and users can choose among four presets.
- Shared components cover transaction rows, section headings, buttons, modal sheets, empty/error states, charts, and budget progress.
- The main shell keeps five tabs alive, offers a persistent add-transaction action, and has a configurable Home section order.
- Tests already cover accessibility large text, reduced motion, contrast, dashboard layout, chart labels, financial calculations, and UI regressions. Preserve their intent and expand coverage only as needed during implementation.
- Existing flows include SMS import, local ledger and backup import/export, authentication, assistant privacy controls, recurring items, bills, and updates. These behaviors are outside visual redesign scope.

## Current design-system findings

| Area | What the local source shows | Audit finding / design opportunity |
|---|---|---|
| Color and themes | `app_palette.dart`, `app_colors.dart`, `theme_provider.dart`; palette-specific light/dark surfaces, shared financial semantics | Preserve every palette identity and ID. Consolidate usage around explicit semantic roles and verify each mapped role for contrast in both modes. |
| Typography | `app_typography.dart`, `app_text_styles.dart`; Poppins default, Inter/Outfit/Space Grotesk/DotGothic16 options; tabular numerals | Keep user-selected font presets. Establish clearer roles and audit the smallest 10–12.5sp styles against dense screens and large system text. |
| Spacing and geometry | 4dp base spacing tokens; 12/18/24/30 radii; page and home-specific spacing | Reduce screen-specific metric exceptions and excessive pill/large-radius use. Retain adaptive bottom insets where needed for nav/FAB clearance. |
| Surfaces | `GlassCard` has border, shadow, optional sheen, conditional `BackdropFilter`; `GradientHeroCard` has layered gradient and glow | Make plain semantic surfaces the default. Reserve translucency and gradients for a small number of clearly purposeful controls or focal states. Avoid card-within-card nesting. |
| Background | `AppBackground` paints multiple radial washes outside AMOLED mode | Use a quieter, stable canvas so chart and money colors carry the emphasis. Keep per-theme character through surface and accent mapping rather than ambient decoration. |
| Navigation | Five persistent destinations, floating translucent pill, uppercase labels set to 10sp, selected tint/pill/glow and animated transitions | Reassess label legibility and selected-state complexity. Keep all destinations and the add action discoverable; give selection a clear non-color cue and reliable 48dp targets. |
| Components | Shared transaction, budget, chart, input, sheet, button and state widgets | Standardize component roles, state treatment, density and semantics before retuning individual screens. |
| Hard-coded styling | Broad screen/widget searches find some direct colors and local `fontSize` overrides in addition to token calls | Inventory and classify exceptions during implementation; retain truly semantic colors and remove ad hoc visual values. No exhaustive count is claimed in this pass. |

## Screen-by-screen audit and redesign intent

The observations below are based on the screen code and shared components, not a rendered build. “Focus” describes the redesign opportunity rather than a claim that the current interaction is broken.

| Screen / flow | Existing responsibility and patterns | Redesign focus |
|---|---|---|
| Home / dashboard | Cycle balance, quick actions, budget, categories, seven-day spending, recent activity; user can reorder/hide dashboard sections; SMS sync/import prompt | Make the financial period and headline amount immediately interpretable; order the next useful action and recent activity ahead of secondary metrics; keep dashboard edit discoverable but out of the scan path. |
| Bills (main tab) | Bills, detected bill information and plan editing | Distinguish due date, amount, recurrence, and detection confidence in a compact list; make detected versus user-confirmed information explicit. |
| Insights (main tab) | Month totals, comparison, top categories, charts, smart tip and routes to summary/assistant | Lead with a plain-language conclusion and comparison period; provide units/context and non-color chart labels; remove any chart or stat that does not change a decision. |
| Cards / payment instruments (main tab) | Payment-method, bank, and account spending summaries; empty states | Explain that this is spending by recorded instrument, not a stored payment card, where needed; use aligned rows and comparable totals. |
| Settings (main tab) | Profile image/name, connectivity, assistant, budgets, recurring, appearance, backup/import/export, app updates and other settings routes | Group by user task and risk; make data movement, privacy, and destructive actions easy to distinguish; avoid one long undifferentiated list. |
| Activity / transactions | Search, sort, date/category/type/amount filters, empty/loading/error results and transaction opening | Prioritize search and active-filter visibility; state sort and filter choices; improve scan alignment for merchant, date, and amount; keep clear/reset controls predictable. |
| Add transaction sheet | Manual income/expense entry, amount, merchant, category | Make type, amount, and save action the clear sequence; ensure keyboard, validation, large text and sheet height work together. Preserve parsing and ledger writes. |
| Transaction details/edit | Merchant, amount, metadata, category, exclude-from-insights control, optional original SMS and review state | Give edit mode and saved state clear hierarchy; explain exclusion and sensitive SMS visibility; make destructive actions explicit. |
| Budgets | Overall/category limits, salary-cycle period, warning threshold, edits and deletion confirmation | Pair amount spent with amount remaining and period; show threshold as text as well as progress; make over-budget and empty states actionable. |
| Recurring | Recurring plans/detection and plan editor | Separate expected schedule from confirmed transactions; surface frequency and next occurrence before metadata; distinguish detected suggestions from saved plans. |
| Summary / export | Financial summary and JSON backup/export | Present period and included data before export; keep privacy explanation close to the action; report success/failure in plain language. |
| Assistant | Finance questions and tool/card responses over local ledger | Keep source period and data scope clear; use readable answer, transaction evidence and follow-up controls; differentiate uncertain answers without color alone. |
| Assistant privacy | Consent and destructive privacy/data choices | Explain what information is accessed or removed immediately beside each choice; use explicit confirmation and cancellation paths. |
| AI settings | Assistant configuration and credential clearing | Keep configuration state, privacy implications, and destructive reset separate and clearly labeled. Do not change model, endpoint, or permission settings in this redesign. |
| Appearance / themes | System/light/dark selection, palette selection, font preset, reset | Preview actual components and text in each saved palette; preserve all IDs; show selected mode and palette with shape/check state plus semantics. |
| Typography preview | Font and scale preview | Use representative amounts, transaction rows, chart labels, and settings text; avoid presenting a typeface sample without realistic small-size behavior. |
| Sound settings | Sound cues and preference controls | Group by behavior, expose current state clearly, keep sound optional and respect system mute/interaction expectations. |
| Authentication | Sign-in/create account, email/password, reset flow and notices | Maintain predictable keyboard traversal, password-manager/paste support, visible labels and inline errors; handle small screens and keyboard insets. |
| Launch / loading | Startup state and app launch artwork | Keep startup motion short and optional; present recoverable loading failures with an action instead of indefinite decoration. |
| Update | Update availability/progress/failure and backup-related messaging | Make current state and next action explicit; preserve update and backup logic; keep error/retry actions prominent. |
| Amount input dialog | Shared amount entry | Use labeled input, currency context, validation near input, large hit targets, and safe keyboard insets. |
| Activity filter sheets | Date, category, type, amount filters | Keep current selections visible; use explicit Apply/Clear actions and a reachable dismiss path. |
| Plan editor / salary-day prompt | Recurring-plan setup and salary-cycle setup | Use progressive disclosure and inline validation; explain which downstream period labels or reminders the setting affects. |
| SMS import prompt / notices | Permission and sync guidance, import outcomes | Explain permission purpose before the system prompt; make retry/settings route and sync state understandable; never imply access beyond the existing behavior. |
| Confirmations / snackbars / empty/error states | Settings, budget, assistant and import flows | Apply consistent severity, action placement, undo where available, and screen-reader announcements; maintain useful recovery copy. |

## Accessibility and usability findings

### Positive evidence

- The source contains custom `Semantics` wrappers for navigation, actions and chart/progress summaries.
- `FloatingNavBar` targets at least 48dp and grows with large system text; `AppMotion` checks the platform's disable-animations preference.
- `GlassCard` removes blur in high-contrast mode and avoids blur on mostly opaque fills.
- Accessibility-focused tests exist for large text, animation reduction, contrast and labels on several charts/progress elements.

### Risks to review on all flows

- Small supporting roles exist at 10sp, 11sp, and 12.5sp. Confirm readability and scaling on the smallest phone and with the largest system text; don't solve density by shrinking labels.
- Theme contrast tests cover important colors, but every composed surface, selected/disabled/focus state, chart, overlay and palette needs a visual and semantics pass.
- Charts need useful text summaries and labels for meaningful marks, and must not rely only on hue. Verify Insights, Home, payment instrument breakdowns, and all chart tooltips with TalkBack/VoiceOver.
- Review the full screen-reader traversal order for bottom navigation, quick actions, transaction rows, editable controls, sheets, and confirmation dialogs.
- Check touch area bounds for compact filter controls, chart elements, icon buttons and theme swatches; visuals may be smaller than their hit targets.
- Check that keyboard opening, system insets, portrait/landscape changes, and text scaling do not obscure sheet actions or create overflow.

## Prioritized recommendations

1. Reconcile this source baseline with the reported OTA build 2.0.23 (build 48) before approving design changes.
2. Agree on one restrained, information-first visual direction and token contract while preserving all stored palette identities, mode options and financial semantics.
3. Redesign the shell and Home first: navigation hierarchy, period context, balance, primary actions, budget status, recent transactions.
4. Standardize transaction rows, section headers, list surfaces, form controls, buttons, sheets and empty/error states.
5. Apply the same hierarchy to Activity, Bills/Recurring, Budgets, Insights, Cards and Summary; maintain all current calculations and routes.
6. Rework settings, authentication, assistant/privacy, appearance, sound and update flows around clear grouping and explicit state.
7. Validate every theme and critical state with small screens, large text, TalkBack/VoiceOver, high contrast, reduced motion and a mid-range Android device. Record actual results rather than infer them from source.

## Evidence and limits

### Skills and tooling discovery

- Read and applied the installed `using-superpowers`, `design`, and `ui-ux-pro-max` skill instructions. The UI/UX skill supplies Flutter stack guidance and directs accessibility, touch-target, contrast, responsive-layout, reduced-motion, and testing checks.
- The catalog contains no dedicated Flutter implementation, Material 3 theming, native accessibility, Flutter responsive-layout, Flutter animation/performance, or Flutter testing skill. `mobile-native` and `animation-performance` were checked but are explicitly web/CSS focused, so they are not being presented as Flutter expertise.
- Available tools include web reference research and the Inspo production-site archive. The archive was not used because this repository already has a developed token system and the integration instructs users to follow an existing project's system. No Figma MCP tool/connected SpendSense file was available in the discovered tools.
- `flutter --version` and `dart --version` could not run because those executables are not on this shell's PATH. The Flutter/Dart SDK versions therefore remain unverified. Existing Flutter tests were inventoried but not run; this pass changes documentation only.

Repository sources reviewed include `pubspec.yaml`, `main.dart`, `theme_provider.dart`, `app_palette.dart`, `app_colors.dart`, `app_spacing.dart`, `app_text_styles.dart`, `app_typography.dart`, `app_background.dart`, `floating_nav_bar.dart`, `glass_card.dart`, `gradient_hero_card.dart`, and all files in `lib/screens/` and `lib/widgets/` by inventory/search. Relevant existing tests include `accessibility_large_text_test.dart`, `reduced_motion_test.dart`, `appearance_test.dart`, `filled_contrast_test.dart`, `category_bars_test.dart`, `animated_progress_bar_test.dart`, `insights_card_layout_test.dart`, `home_action_dock_layout_test.dart`, and `redesign_test.dart`.

The supplied official product references were reviewed for public positioning and visible product hierarchy. Public websites do not provide a complete, inspectable current in-app UI for all four products, so this report treats them as principles and publicly presented product imagery rather than claiming a screen-by-screen app teardown. No local Figma integration or Flutter command-line executable was found in the available tools/environment for this pass.

## Reference links

- [Flutter UI](https://docs.flutter.dev/ui)
- [Flutter accessibility](https://docs.flutter.dev/ui/accessibility)
- [Material Design 3 foundations](https://m3.material.io/foundations/)
- [Material 3 typography](https://m3.material.io/styles/typography/applying-type)
- [Apple HIG design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles/)
- [Apple HIG layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Apple HIG charts](https://developer.apple.com/design/human-interface-guidelines/charts)
- [Revolut](https://www.revolut.com/)
- [Monzo](https://monzo.com/)
- [N26](https://n26.com/)
- [Apple Wallet](https://www.apple.com/wallet/)
