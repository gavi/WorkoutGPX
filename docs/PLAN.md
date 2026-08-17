# WorkoutGPX — Product & Engineering Plan

_Last updated: 2026-08-17 (items 1.1, 1.2, 1.6, 2.4, 2.7, 2.8 and 3.3 landed in the working tree; deployment target now iOS 16.0). Current shipping version: 1.3._

This document captures a first-principles view of what WorkoutGPX is, where the
current implementation falls short of that, and a sequenced plan to close the gap.
It is meant to be edited as decisions are made and work lands.

---

## 1. What the app is

WorkoutGPX is a **bridge across a boundary**: Apple Health (closed, per-device,
rich) → the open world (GPX, the lingua franca of routes). Nothing more.

Its value can be written as:

```
value = completeness × fidelity ÷ friction   (all multiplied by trust)
```

| Dimension | Question it answers |
|---|---|
| **Completeness** | Does everything on the Health side get across? |
| **Fidelity** | Is what crosses *correct* and lossless where the format allows? |
| **Friction** | How many taps from intent to file-in-the-right-place? |
| **Trust** | Will people believe the output, keep the app, and recommend it? |

Every proposed change below is justified against one of these four. Individual
user requests (e.g. "keep my filter after export") are instances, not the goal.

**Target statement:** _"Your workouts as files — complete, faithful, automatic, private."_

Three modes of use the app should eventually support:

1. **Browse & pick** — what exists today.
2. **Bulk** — export everything matching a filter in one action.
3. **Continuous** — new workouts are exported automatically to a folder.

### Non-goals

- Cloud sync, accounts, or any network traffic. Being fully on-device is the moat.
- Editing or writing back to HealthKit (GPX → Health import is a possible
  future direction but is explicitly out of scope for this plan).
- Becoming a training-analysis app. Charts are only for verifying what will be exported.

---

## 2. Current-state audit

Grounded in the code as of 1.3.

### Completeness

| Issue | Where | Impact |
|---|---|---|
| ~~Fetch capped at 500, newest-first, no warning~~ (fixed 2026-08-17) | `HealthStore.fetchWorkouts` | Users with long histories silently lose the **oldest** workouts — the exact ones people go looking for. |
| ~~Only running / walking / hiking / cycling queried~~ (fixed 2026-08-17) | `HealthStore.fetchWorkouts`, `WorkoutFilterView` | Open-water swims, rowing, paddle, skiing, skating, wheelchair, golf, "other" all have routes in Health and are invisible here. |
| ~~Only lat/lon/ele/time exported~~ (heart rate, cadence, power, speed, course added 2026-08-17) | `GPXGenerator.buildGPX` | Heart rate, cadence, power, temperature, running dynamics, laps/events, source device are left behind. Only `workoutType` and `workoutRoute` are requested in `HealthStore.requestAuthorization`. |
| "No route data" conflates three states | `WorkoutDetailView.loadRouteData`, `HealthStore.fetchRouteData` | Route permission denied, third-party workout with no route, and query error all look identical to the user. |

### Fidelity

| Issue | Where |
|---|---|
| Track `<name>` interpolates a raw Swift `Date` description | `GPXGenerator.swift` (`<name>… \(workout.startDate)</name>`) |
| `ISO8601DateFormatter()` allocated per track point | `GPXGenerator.generateGPX` inner loop |
| No `horizontalAccuracy` filtering on export (map view smooths grades, file doesn't) | `GPXGenerator`, `HealthStore.fetchRouteData` |
| Filename carries `_km` / `_mi` although GPX is always metres | `GPXGenerator.exportGPX` |
| End date carries time-of-day, so "through the 14th" excludes the afternoon of the 14th | `ContentView.filteredWorkouts`, HK predicate in `HealthStore.fetchWorkouts` |
| Filtering is done twice (HK predicate + in-memory) and can disagree | `ContentView.filteredWorkouts` vs `HealthStore.fetchWorkouts` |

### Friction

| Issue | Where |
|---|---|
| Per-workout export only: filter → scroll → open → export → share → destination, × N | `WorkoutDetailView` share button |
| Every export is already written to `Documents/` but the folder is not exposed in Files | Missing `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` in Info.plist keys (project.pbxproj) |
| Scene activation triggers a full refresh with `isLoading = true`, rebuilding the list (and likely popping the detail view) after every export | `ContentView.onChange(of: scenePhase)` |
| Quick date presets are all relative to "now"; no way to step back through history | `WorkoutFilterView` presets |
| Filters reset on relaunch; no indicator that a non-default filter is active | `ContentView` `@State` |
| No Shortcuts / App Intents surface | — (requires iOS 16) |

### Trust

| Issue | Where |
|---|---|
| On-device / no-network story is not stated anywhere in the app | `SettingsView`, README |
| Exports contain exact start/end coordinates (home address) with no trim option | `GPXGenerator` |
| Authorization state is inferred by a heuristic sample query | `HealthStore.checkAuthorization` |
| No test target despite `CLAUDE.md` documenting test commands | repo |

### Structure

- `ContentView` owns fetching, filtering, and filter state; GPX generation is
  free functions; route fetch is completion-based while the rest is async/await.
- `NavigationView` (deprecated) with `StackNavigationViewStyle`; iPad/Mac get a
  phone layout.
- Sample GPX fixtures already exist (`WorkoutGPX/Samples`) and are the natural
  basis for unit tests.

---

## 3. Plan

Three phases. Each is independently shippable. Items within a phase are roughly
ordered by value ÷ effort.

### Phase 1 — Trust & correctness pass (target: 1.4)

Small, low-risk changes that fix things users currently can't see are wrong.

| # | Task | Dimension | Notes / acceptance |
|---|---|---|---|
| 1.1 | Keep user-chosen date range across exports | Friction | **Done** in working tree: `ContentView` only advances `endDate` on activation if it already points at today. |
| 1.2 | Remove the 500 cap | Completeness | **Done** (2026-08-17): `HKObjectQueryNoLimit`; the type predicate is gone too — the query is date-only and types filter in memory. |
| 1.3 | Inclusive end date | Fidelity | Normalise `endDate` to end-of-day for both the HK predicate and in-memory filter. Acceptance: a workout at 17:00 on the chosen end date is listed. |
| 1.4 | Expose `Documents/` in the Files app | Friction | Add `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`. Acceptance: previously exported GPX files are visible under Files › On My iPhone › WorkoutGPX. |
| 1.5 | Distinguish no-route vs no-permission vs error | Trust | Check `authorizationStatus(for: .workoutRoute())` and the workout's `sourceRevision`; show three distinct empty states with the right CTA. |
| 1.6 | GPX generator hygiene | Fidelity | **Mostly done** (2026-08-17): generator rebuilt on [CoreGPX](https://github.com/vincentneo/CoreGPX) (single date formatter, escaping/CDATA handled by the library); human-readable `<name>`; `<metadata>` with `desc`/`time`/`link`; track `<type>`/`<desc>`/`<src>`; elevation only when `verticalAccuracy >= 0`. Still open: filename `_km/_mi` suffix (kept for continuity), `horizontalAccuracy` filtering (see D4). |
| 1.7 | Quiet refresh on scene activation | Friction | Re-check auth and refetch without flipping `isLoading`; keep list identity so a pushed detail view survives. |
| 1.8 | Filter-active indicator | Trust | Fill the filter toolbar icon / show a badge when types or dates differ from default. |
| 1.9 | Privacy statement | Trust | **Settings done** (2026-08-17). Still open: README wording and checking the App Store privacy label. |
| 1.10 | Rating prompt | Growth | `SKStoreReviewController.requestReview` after a successful export, rate-limited (e.g. once per version, after ≥ 2 exports). |
| 1.11 | Test target | Structure | Add `WorkoutGPXTests`; unit-test `generateGPX` against sample fixtures (segment count, point count, ISO times, escaping) and the date-normalisation helpers. |

### Phase 2 — Bulk & navigation (target: 1.5)

| # | Task | Dimension | Notes / acceptance |
|---|---|---|---|
| 2.1 | Multi-select export | Friction | Edit mode in the list, "Select all" for the current filter, one share sheet with N `.gpx` URLs (option: single `.zip`). Progress UI for route fetching; skip-and-report workouts without routes. |
| 2.2 | Persist filters across launches | Friction | Store dates + selected types in `UserDefaults`; on launch apply the same "advance end date only if today" rule. Pair with 1.8 so a stale filter is never invisible. |
| 2.3 | Period steppers | Friction | ‹ / › buttons that shift the current range by its own length (week/month/year); a year picker for jumping straight to e.g. 2021. |
| 2.4 | All activity types | Completeness | **Done** (2026-08-17): all workouts are fetched; chips are built from the types present in the range (with counts), "All" = empty selection; names/icons cover the full `HKWorkoutActivityType` set. Workouts without a route are hidden by default with a visible "N without GPS hidden" note and a toggle to show them (see 2.7). |
| 2.5 | Extract `WorkoutRepository` + `GPXExporter` | Structure | Move fetch/filter/export out of views; single async API for routes. Prerequisite for 2.1 and Phase 3. |
| 2.6 | `NavigationStack` / `NavigationSplitView` | Structure | Requires iOS 16 (see decision D1). Proper iPad and Mac Catalyst layouts. |
| 2.8 | Route viewer parity with GPXExplore | Trust | **Done** (2026-08-17): ported from `~/work/multiplatform/GPXExplore` — Swift Charts elevation profile with drag-to-scrub and a live map marker (`ElevationOverlay`), extracted `RouteInfoOverlay`, effort **and** pure-elevation gradient renderers, peak/valley markers, fit-to-route, view menu in the detail toolbar. Settings: route colouring mode, track line width, chart detail, default overlay visibility. Overlays and chart data are cached and rebuilt only when the route or settings change (GPXExplore rebuilt them per hover). Not ported: waypoints, user-location tracking, drag-zoom (macOS-only in the source). |
| 2.7 | Route presence decides visibility | Trust | **Done** (2026-08-17): one `HKWorkoutRoute` query per fetch, matched to workouts by time containment (±60 s) preferring the same source bundle (`HealthStore.matchRoutes`). Route-less workouts are hidden by default, counted in the UI, and marked with `location.slash` when shown. HealthKit has no reverse route→workout link, so this avoids one query per workout. |

### Phase 3 — Continuous & richer data (target: 2.0)

This is the version that changes what the app is.

| # | Task | Dimension | Notes / acceptance |
|---|---|---|---|
| 3.1 | Auto-export new workouts | Friction | `enableBackgroundDelivery` for `workoutType` + `HKObserverQuery`; on new workout with a route, write GPX into a user-chosen folder (security-scoped bookmark to iCloud Drive / Files). Opt-in toggle in Settings; log of what was exported. See decision D2. |
| 3.2 | Shortcuts / App Intents | Friction | "Export latest workout", "Export workouts between dates" returning `IntentFile`s. Requires iOS 16. |
| 3.3 | Heart rate / cadence / power in GPX | Completeness | **Done** (2026-08-17): reads heart rate, running power (iOS 16), cycling power + cadence (iOS 17) via `HKQuantitySeriesSampleQuery` (workout-associated samples first, time-range fallback); emits `gpxtpx:hr/cad/speed/course` (TrackPointExtension v2), `gpxpx:PowerInWatts` and the de-facto bare `<power>`; nearest sample within 15 s. Settings toggle "Include Sensor Data" (default on). Weather temperature goes in `<desc>` (single value per workout, not per point). |
| 3.4 | Privacy zone / trim | Trust | Optional "trim first and last N metres" per export or as a default; visualise trimmed portion on the map. |
| 3.5 | Additional formats (TCX / FIT) | Fidelity | Optional. Strava/Garmin ingest HR + laps most faithfully via FIT. Keep GPX as the default and the brand. |
| 3.6 | Localisation | Growth | String catalogs are already enabled; add the top App Store languages once strings stabilise. |

---

## 4. Open decisions

| ID | Decision | Options | Impact |
|---|---|---|---|
| **D1** (decided 2026-08-17) | Raise deployment target 15.6 → 16.x? | — | **Moved to iOS 16.0** to ship the Swift Charts elevation profile. Unlocks App Intents and `NavigationStack` for later phases. |
| **D2** | Is auto-export in scope? | Yes (Phase 3) / keep the app deliberately manual | Changes the product's identity from "tool" to "infrastructure". Also raises support surface (background delivery reliability, folder permissions). |
| **D3** | Bulk export packaging | N files in one share / single zip / both | Zip is friendlier for AirDrop and mail; N files is friendlier for "Save to Files". |
| **D4** | Accuracy threshold for point filtering | Fixed 50 m / configurable / off by default | Trade-off between clean tracks and "you dropped my points". Default should be conservative and visible. |
| **D5** (decided 2026-08-17) | How to encode power in GPX | — | Both: Garmin `gpxpx:PowerExtension` (schema-valid) **and** bare `<power>` (what Strava/Zwift/RideWithGPS exchange; not schema-valid, so strict validators flag it). Revisit if a consumer chokes on the duplicate. |

---

## 5. Working agreements

- Simulator ignores filters and uses `Samples/` — anything touching HealthKit
  queries or date filtering must be verified on a device before release.
- Behaviour changes that could hide data (caps, accuracy filtering, trimming)
  must be visible in the UI, never silent.
- Each phase ships on its own; do not block Phase 1 fixes on Phase 2 refactors.
- Keep this file current: mark tasks done, record decisions in §4 with the date.
