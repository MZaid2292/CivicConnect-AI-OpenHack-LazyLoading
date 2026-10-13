# CivicConnect AI — Flutter MVVM + BLoC hackathon MVP

Citizens report civic issues (potholes, streetlights, garbage, drainage), the
municipality verifies, prioritises and assigns them, and contractors deliver
evidence-backed fixes that are inspected before the citizen sees "Resolved".

**This build is frontend + local mock workflows only.** No backend, no real
authentication, no payment gateway, no paid APIs. Supabase is a later phase.

## Start on Windows
1. Open the `civicconnect_ai` folder in VS Code.
2. Ensure the **Flutter SDK** is installed (`flutter doctor`; developed on Flutter 3.35 / Dart 3.9).
3. Run:
   ```powershell
   flutter pub get
   flutter analyze
   flutter test
   flutter run -d chrome   # or an Android device/emulator
   ```
   (`scripts\setup_windows.bat` also works. Run `flutter create --project-name civicconnect_ai --platforms android,web .` only if the `android/` or `web/` folders are missing.)

## 2–3 minute live demo script
1. **Welcome → Skip to demo role selector → Continue as Citizen.**
2. Tap **Report issue**. Type the title *"Big potholes on Canal Road service lane"*.
   - The **Category suggestion** card (rule-based NLP) picks *Potholes & road damage* and shows the matched words.
   - **Estimated priority** shows the score breakdown.
   - **Pin on map** near Canal Road (or tap *Use my location*; if permission is denied the form explains and offers manual pinning / ward centre).
   - A **Possible duplicate** card appears for CMP-1005 with distance, category and wording overlap. Choose *Support this instead* or *Report anyway*, then **Submit**.
3. Account menu → **Switch role / log out → Municipal Admin.**
   - **Overview** KPIs; **Queue** already contains the new report (same in-memory repository).
   - Open it → **Verify** (route to department) → **Assign contractor** (or **Open tender** for bids).
   - **Duplicates** tab shows CMP-1008 vs CMP-1005 with an explained score — merge or keep.
   - **Rules** tab: drag a slider (e.g. *Per supporter*) and watch the live preview re-rank reports; **Save & re-score**.
4. Switch to **Contractor** → Dashboard *Next actions* → **JOB-504** → **Start work** → **Add after photo** → **Request inspection**. Try **Available** to submit a mock bid on JOB-505.
5. Switch to **Admin** → Overview *Ready for inspection* → **Inspect** → compare before/after → **Accept & resolve** (or **Request rework**).
6. Switch to **Citizen** → My reports → **CMP-1001** (resolved) → rate ★★★★★. **Transparency** tab shows the public activity log.

The demo role survives an app restart; *Switch role / log out* clears it. Report data resets on restart.

## What is real vs. simulated
| Area | Status |
|---|---|
| Category classification | Real algorithm — explainable keyword/phrase weights over title + description (`KeywordCategoryClassifier`). Text only; **no image AI**. |
| Duplicate detection | Real algorithm — Haversine distance (≤300 m), category match, Jaccard token similarity (`DuplicateDetector`). Falls back to text-only matching when no precise location. |
| Priority | Real algorithm — category base + severity words + supporters + days open, thresholds editable by admins (`PriorityEngine`, `PriorityRules`). |
| Workflow rules | Real state machines with role checks (`ComplaintWorkflow`, `JobWorkflow`), enforced in services **and** mock repositories. Client checks are **not** a security boundary — the backend must enforce them. |
| Login / sign-up | **Mock forms** — format validation only; nothing is stored or sent. |
| Demo role | SharedPreferences stores the chosen *demo role* and an onboarding flag only — **not identity, not authentication**. |
| Data | In-memory seeded repositories (10 reports, 6 jobs, 4 contractors); resets on restart. |
| Photos | Picked via `image_picker`, held **in memory only**, labelled "Local only · not uploaded". Seed images are labelled illustrations. |
| Payments / earnings | **Simulation labels only** (Held / Released). No money moves. |
| Maps | `flutter_map` + OpenStreetMap tiles with attribution; tile URL configurable in `AppConfig` (set `null` for offline grid). No bulk tile requests. |

## Design system
Material 3 with custom tokens, in `lib/core/theme/`:
- `app_theme.dart` — complete light **and** dark `ColorScheme`s (Civic Blue primary, Teal secondary, Emerald tertiary), typography scale, and component themes (cards, inputs, buttons, chips, navigation, dialogs, sheets, menus, snackbars). `CivicPalette` (a `ThemeExtension`) adds muted/subtle text, borders, semantic success/warning/danger/info, hero gradient and shadows; `palette.tone(hue)` lightens status hues for dark surfaces. Read via `context.colors`, `context.textStyles`, `context.civic`.
- `tokens.dart` — spacing (`Space`), radii (`Radii`), breakpoints (`Breakpoints`: 600 / 900 / 1200), and motion (`Motion.of(context, …)` returns zero when the OS asks to reduce motion).

**Light/dark mode follows the operating system** (`themeMode: ThemeMode.system`) and updates live when the OS setting changes. It is intentionally *not* stored in SharedPreferences. Status/navigation bar icon brightness follows the theme. OSM tiles are darkened with `darkModeTileBuilder` in dark mode.

Reusable components (`lib/core/widgets/`): `CivicAppBar`, `CivicCard`, `CivicHeroCard`, `CivicButton`, `CivicTextField`, `CivicStatCard`, `CivicSectionHeader`, `CivicEmptyState`, `CivicLoadingState`, `CivicErrorState`, `CivicIconBadge`, `CivicAvatar`, `InfoBanner`, `Pill`, `AdaptiveGrid`, `CivicResponsiveScaffold`, `CivicBottomNavigation`, `CivicNavigationRail`, `CivicImagePickerCard`, `EvidenceGallery`. Complaint-specific: `CivicComplaintCard`, `CivicStatusBadge`, `CivicTimeline`, `StatusTracker`, `PriorityMeter`, `SmartInsightCard`, `CategoryMatchBars`.

Responsive navigation: bottom bar below 600 px, navigation rail 600–1199 px, full sidebar from 1200 px. On short windows (landscape phones) the rail hides its header and unselected labels and can scroll. The admin queue switches to a table from ~960 px content width. Orientation is never locked.

Large text: layouts are checked at 320 px with 2.0× text. Short labels (pills, buttons, captions) get an extra line instead of being cut off (`adaptiveLines`), and app bar actions collapse to icon buttons with tooltips (`CivicAppBarAction`).

Web URLs: pushed screens update the address bar (`GoRouter.optionURLReflectsImperativeAPIs`), and a reload of a deep link such as `/complaint/CMP-1001` waits for the demo session to restore (`/loading?from=…`), then opens that screen. Role guards still apply. With no saved demo role, the role selector is shown first. The card-to-detail Hero animation only runs for in-app navigation; a fresh load has no source card, so it's skipped. Detail screens opened directly show a back button that goes home.

## Architecture
MVVM + flutter_bloc. Views never call repositories in `build`; Cubits subscribe to repository streams.

```
lib/
  app/app.dart                  MultiRepositoryProvider + MaterialApp.router
  core/
    config/app_config.dart      tile URL, default map centre (non-secret)
    di/app_dependencies.dart    composition root — ONE instance of each repo/service
    data/                       InMemoryCollection (reactive store), DemoSeed
    models/                     AppRole + demo Actor, MediaAttachment, WorkflowException, permissions
    presentation/watch_cubit.dart  generic stream → loading/ready/failure view model
    router/app_router.dart      go_router + session redirect & role guards
    services/                   LocationService (geolocator), MediaPickerService (image_picker)
    theme/, utils/, widgets/    design system, geo/text/formatting, shared widgets & map
  features/
    auth/          session repo (demo role), SessionCubit, welcome/login/role screens
    complaints/    domain: Complaint, ComplaintWorkflow, repository contracts,
                   services (classifier, duplicates, priority, ComplaintService)
                   data: mock repositories; presentation: list/detail cubits, widgets
    jobs/          domain: WorkJob (contract + simulated payment state), Contractor,
                   JobWorkflow, JobService; data: mocks; presentation: job detail
    citizen/       create/edit-draft form view model, location picker, citizen tabs
    admin/         dashboard stats, queue, duplicate review, work/contractors, rules editor, inspection
    contractor/    dashboard, available tenders, my jobs, profile, mock earnings
    notifications/ in-app inbox
    transparency/  public stats + activity log
    shell/         responsive role shell (bottom bar < 600 px, rail, sidebar ≥ 1200 px)
```

### State machines
Complaint: `Draft → Submitted → Verified → Assigned → In progress → Awaiting inspection → Resolved`, with `Submitted/Verified → Rejected | Merged duplicate` and `Awaiting inspection → Rework required → In progress`.

Job (contract, separate): `Open for bids → Awarded → In progress → Completion submitted → Completed`, with `Completion submitted → Rework requested → In progress` and `Open/Awarded → Cancelled`. Payment state (simulated) is a third, separate field.

### Moving to Supabase later
Implement `ComplaintRepository`, `JobRepository`, `ContractorRepository`, `NotificationRepository`, `PriorityRulesRepository` and `SessionRepository` against Supabase and swap them in `AppDependencies`. Then:
- Supabase Auth owns the session (`onAuthStateChange`); roles come from a protected table, not SharedPreferences. Remove the demo role selector.
- Mirror `ComplaintWorkflow.transitions` / `JobWorkflow.transitions` in RLS policies or RPC functions.
- Upload `MediaStorage.localMemory` photos to Storage and switch them to `remoteUpload`.
- Never commit keys; pass them with `--dart-define`. `supabase_flutter` is listed but intentionally **not initialised**.

## Tests
`flutter test` runs:
- `test/domain/nlp_services_test.dart` — classifier, Jaccard, duplicate detector (incl. GPS fallback), priority engine & configurable rules.
- `test/domain/workflow_test.dart` — illegal transitions, role permissions, full lifecycle incl. rework loop, tender→bid→award, duplicate merge, rules re-scoring, contractor approval.
- `test/widget_test.dart` — onboarding, role restore + logout, all dashboards at phone and desktop widths, report creation reaching the admin queue, GPS-denied fallback, duplicate warning.
- `test/demo_flow_test.dart` — the live-demo workflow through the real UI and dialogs.
- `test/theme_test.dart` — light/dark token contrast (WCAG), light & dark rendering, live OS theme switching, every dashboard in dark mode.
- `test/responsive_test.dart` — all three dashboards and the detail screens at 320, 375, 768, 1024 and 1440 px (asserting bottom bar / rail / sidebar), landscape phone, 320 px onboarding.
- `test/forms_accessibility_test.dart` — report form at 320 px with 1.3× and 2.0× text and the keyboard open, login form at 2.0×, bid sheet at 1.5×, semantics labels.
- `test/audit_test.dart` — every tab and detail screen of all three roles scrolled end-to-end at 320 px with 2.0× text, and in landscape at 740×360, 915×412 and 1280×800; web deep-link reloads (including role guards and the no-role case); Hero kept for in-app navigation; duplicate merge confirmation / keep separate; rules editor draft → save.

## Known limitations
- All data is in memory; restarting the app restores the demo role but resets reports.
- Priority "age" points are recalculated when data changes or rules are saved, not on a timer.
- The NLP is keyword-based (English). It is explainable by design but will miss unusual phrasing; citizens can always override the category.
- Push notifications (`flutter_local_notifications`) are not wired; the in-app inbox is.
