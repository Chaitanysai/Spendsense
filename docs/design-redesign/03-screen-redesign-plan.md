# SpendSense screen redesign plan

This plan applies to the local screen inventory in `lib/screens/` and shared UI in `lib/widgets/`. Reconcile against the reported OTA build 2.0.23 (build 48) before implementation.

| Stage | Screens and shared components | Acceptance focus |
|---|---|---|
| 0. Source alignment | Compare local checkout with installed OTA; confirm current features, screens, themes and persisted settings | Approved baseline and complete inventory; no business logic or user changes discarded |
| 1. Foundation | `main.dart`, `AppPalette`, `AppColors`, `AppSpacing`, `AppText`, `AppTypography`, `AppBackground`, `GlassCard`, `GradientHeroCard`, `AppButton`, `TransactionTile`, `SectionHeader`, `AppSheet`, `AppStates` | One semantic theme contract; all existing themes still resolve; routine content surfaces no longer compete; text and controls scale |
| 2. App shell | `FloatingNavBar`, main shell, add FAB | Five destinations remain discoverable; selected state works without color; labels remain readable; content clears navigation/FAB; reduced motion and high contrast work |
| 3. Home and capture | `HomeScreen`, `HomeActionDock`, `CycleHero`, `BudgetSummary`, `QuickActionTile`, category and transaction widgets, `AddTransactionScreen`, amount dialog, SMS prompt | Period/balance/action/recent transaction scan is clear; category and weekly summaries explain values; add/edit and SMS flows retain behavior |
| 4. Transactions | `ActivityScreen`, `TransactionDetailsScreen`, filter sheets | Search, filters, dates, sort, amount and type are explicit; amounts align; all filters and details remain accessible; transaction data unchanged |
| 5. Planning | `BudgetsScreen`, `BillsScreen`, `RecurringScreen`, `PlanEditor`, salary-day prompt | Spent/remaining/limit/period are clear; due and recurring dates scan quickly; detected versus saved states are explicit; warnings and deletion confirmations are understandable |
| 6. Analysis | `InsightsScreen`, `CardsScreen`, `SummaryScreen`, chart/category/progress widgets | Every chart has labels and an accessible summary; values have periods/units; no chart is decorative; export scope and privacy are clear |
| 7. Account and secondary | `SettingsScreen`, `AppearanceScreen`, `TypographyScreen`, `SoundSettingsScreen`, `AssistantScreen`, `AssistantPrivacyScreen`, `AISettingsScreen`, `AuthScreen`, reset dialog, `UpdateScreen`, launch/loading | Settings are grouped; user preferences and all palette identities persist; privacy/permission choices are explicit; forms work with keyboard and large text; update paths preserve behavior |
| 8. Product-wide verification | Every theme, key dialog/sheet/empty/error/loading state, tests and device states | Compact widths, landscape, largest text, TalkBack/VoiceOver, high contrast, reduced motion, contrast, touch targets, and mid-range Android performance reviewed |

## Protected behavior

All stages are presentation-only. Preserve transaction data and calculations, salary-cycle math, budgets, recurring/bill detection, SMS import and permission timing, encrypted/local ledger behavior, authentication, sync, backup import/export, assistant data boundaries, update behavior, palette/font persistence, and existing routes. Do not change app version/build, Firebase, endpoint/model/permission settings, or publish an OTA update as part of the redesign.
