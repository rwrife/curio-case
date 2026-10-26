# Curio Case — PLAN

## Scope

One Flutter codebase (Windows + Android + iOS) for cataloging personal hobby collections: items with photos, condition, storage-location paths, tags, custom per-collection fields, move history, search/filter, stats, and user-owned JSON/CSV export. Strictly offline: zero network requests.

### Explicit non-goals

- No cloud sync, accounts, social sharing, telemetry, ads, or analytics.
- No price-lookup, appraisal, barcode scanning, or AI recognition.
- No lending workflow (`lend-loop`), no single-domain verticals (`wine-vault`, `freezer-map`, `aquarist`, `cutting-log` cover those).
- No React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or native Swift/Xcode-only implementation. Flutter only.

## Architecture

```
lib/
  main.dart                    # platform-aware bootstrap
  app/                         # adaptive-widget layer + theme
    adaptive/                  # AdaptiveScaffold/AdaptiveButton/AdaptiveDialog (Cupertino | Material 3 | Fluent)
  domain/                      # pure Dart: Collection, Item, LocationPath, Condition, Move, StatsModel
  data/                        # SQLite (sqflite_common_ffi on desktop), repositories, JSON/CSV codecs
  features/
    collections/               # collection wall + editor
    items/                     # item grid, detail, add/edit, photo attach
    locations/                 # location tree browsing, move logging
    stats/                     # per-collection dashboards
    settings/                  # backup/export/import, about
  l10n/
```

- **Domain layer** is pure Dart with unit tests — no Flutter imports; condition transitions, location-path parsing, and stats math are deterministic and clock-injectable.
- **Persistence**: SQLite via `sqflite` (mobile) + `sqflite_common_ffi` (Windows/desktop); schema versioned with migrations; photo files in app documents dir referenced by relative path.
- **Adaptive-widget layer** (`AdaptiveScaffold`, `AdaptiveButton`, `AdaptiveDialog`, `AdaptiveNavigation`) switches on `TargetPlatform`: Cupertino on iOS/iPadOS, Material 3 on Android, Fluent (`fluent_ui`) on Windows. Screens written once against the layer.

## Technology choices

- **Flutter 3.47.7 / Dart 3.13.5** (pinned in `toolchain.json`): one codebase for the Windows primary target plus Android/iOS phones and tablets.
- **UX strategy A — platform-native adaptive**: this is a utility/productivity app; users expect each OS's conventions (iOS nav bars + swipe-back, Material 3 + Android back handling, Fluent NavigationView + keyboard shortcuts + hover on Windows). A custom skin would fight those conventions for no benefit.
- `fluent_ui` for Windows widgets; `cupertino_icons`; `image_picker` for camera/gallery; `file_picker`/`path_provider` for backup files; `sqflite` + `sqflite_common_ffi`.
- Identifiers: Android applicationId and iOS bundle ID `com.infinityball.curiocase` (registered `CREATED com.infinityball.curiocase` in App Store Connect); Windows/MSIX identity `cominfinityball.curiocase`.

## Milestones (dependency order)

1. **M1 Skeleton + CI** (issue #1): `flutter create` with windows/android/ios enabled, CI on `windows-latest` (`flutter test` + `flutter build windows --release`) and Android debug build; golden-test harness.
2. **M2 Domain + persistence** (#2): pure-Dart models, stats, migrations, repository tests.
3. **M3 Core workflow** (#3): collection + item CRUD with photos, custom fields, search.
4. **M4 Locations + stats** (#4): location tree, move logging, dashboards.
5. **M5 Platform-authentic UI** (#5): adaptive layer fully wired, per-`TargetPlatform` golden tests, keyboard navigation on Windows.
6. **M6 Backup/export** (#6): JSON backup export/import, CSV catalog export, privacy docs.
7. **M7 Release** (#7): `AppStore/icon.png` wiring into all icon sets, `.github/workflows/release.yml`, store copy review.

## Testing strategy

- Pure-Dart unit tests for domain + codecs (no Flutter).
- Repository tests on `sqflite_common_ffi` in-memory DBs.
- Widget tests per screen; **golden/screenshot tests render key screens with `TargetPlatform.iOS`, `TargetPlatform.android`, and `TargetPlatform.windows`** to prove each platform gets its intended look/behavior.
- Accessibility passes: Semantics labels, text scaling to 200%, full keyboard navigation + focus indicators on Windows, screen-reader labels on stats.

## Packaging / distribution

- Primary: `.github/workflows/release.yml` on `v*` tag or manual dispatch → `windows-latest` → `flutter build windows --release` → zipped portable build attached to a GitHub release (MSIX optional later, identity `cominfinityball.curiocase`).
- Android debug build stays green in CI (`flutter build apk --debug`); Play submission is a later opt-in milestone.
- iOS: compile checks later on a macOS runner using Actions secret names `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`; TestFlight submission is a later opt-in milestone, never required for MVP.
- Store copy lives in `AppStore/description.txt`; icon is the generated `AppStore/icon.png` wired via `flutter_launcher_icons` (Android/iOS) and the Windows runner `.ico` resource.

## Risks

- **Photo storage growth** — mitigate with on-import downscale + documented storage stats; backup export can optionally exclude photos.
- **Custom-field schema drift** — fields are data (EAV-lite), not schema migrations; codec versioning covers it.
- **`fluent_ui` maturity** — adaptive layer isolates it; fallback is a restrained custom Fluent-styled theme behind the same widgets.
- **Windows filesystem paths vs mobile** — location paths are app-logical strings, never OS paths.

## Privacy statement

All user data stays in the app sandbox. No network permission is even requested on Android/iOS manifests. Export is user-initiated to a file the user chooses.
