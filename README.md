# Curio Case

**Pitch:** A collection catalog for hobbyists who keep pins, records, shells, cards, minis, tickets, or stones in boxes and drawers: record what you own, where it lives, and its condition across multiple collections on phone, tablet, and Windows — offline, no accounts, no cloud.

## Motivation

Hobby collectors usually track collections in a notes app, a spreadsheet, or memory. Existing catalog apps are either single-domain (wine, cards, plants), cloud-account-gated, subscription-ware, or desktop-only. Collectors want one honest tool that answers three questions for *any* collection: **what do I have? where is it right now? what shape is it in?** — without uploading their holdings to a server.

## Target users

- Hobby collectors with one or more mixed collections ( enamel pins, vinyl, shells, coins, teapots, action figures, ticket stubs, stones, minis).
- People who lend, move, or re-box items and lose track of physical locations ("which drawer is the display case in?").
- Anyone who wants a private inventory for insurance, moving, or estate purposes without a cloud account.

## Use cases

- Catalog a new acquisition in under a minute: photo, name, condition, acquired-on/date/price (optional), and a storage location like `Studio > Shelf B > Tin 3`.
- Answer "do I already own this?" before a purchase with instant search across all collections.
- Walk a collection by location path when packing, re-shelving, or valuing for insurance.
- Review collection stats: item count, condition spread, acquisitions per year, optional declared-value total the user typed in.
- Tag, filter, and sort with per-collection custom fields (e.g. "label" for vinyl, "karat" for coins).

## How to use (intended workflow)

1. Create a collection and pick its field template (built-in templates or custom fields).
2. Add items: name, photos (camera or gallery), condition, storage location path, tags, optional notes and declared value.
3. Browse by collection wall, grid, or location map; search and filter everything.
4. Log moves when items change location; history stays per item.
5. Export a JSON backup or CSV catalog whenever you want; import restores on any device you own.

## MVP features

- Multiple collections with per-collection custom text fields and built-in templates.
- Items with photos, condition enum, location path, tags, notes, optional acquired date/price and declared value.
- Move history per item (who-where-when, user-entered).
- Search, tag filter, condition filter, sort by name/date/added/value.
- Collection stats dashboard (counts, condition spread, acquisitions per year, declared-value sum).
- Local SQLite storage, versioned JSON backup export/import, CSV catalog export.
- Adaptive layouts for phone, tablet, and desktop windows with touch and keyboard/mouse input.

## Non-goals

- No cloud sync, accounts, social features, price lookups, or marketplace links; the app performs no network requests.
- No barcode/AI recognition, no appraisal claims, no insurance certification.
- No trading/lending workflow (that is `lend-loop`'s job), no single-domain verticals (wine, plants, freezer are separate tools).
- No React Native, Expo, Kotlin Multiplatform, .NET MAUI, or native Swift/Xcode-only builds — this is one Flutter codebase.

## Privacy, permissions, data

- 100% local: SQLite database plus user-entered data; no telemetry, no ads, no analytics, no network calls.
- Permissions: camera and photo-picker access only, requested at first photo add; every feature works without photos.
- Full data ownership via JSON backup and CSV export; import is user-initiated and validated.

## Identifier

- Android applicationId, iOS bundle identifier: `com.infinityball.curiocase`; Windows identity `cominfinityball.curiocase`.
- App Store Connect registration: `CREATED com.infinityball.curiocase` (2026-10-26).
- iOS release automation uses the repository Actions secret names `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` (values are never committed or logged).

## Status and milestones

The catalog now uses the existing SQLite domain/store on Windows, Android, and iOS. Create, rename, and delete collections; define collection-specific text fields; add, edit, and delete items with optional photos, condition, tags, notes, acquisition date, and declared value. Search covers item names, tags, notes, and custom fields across collections, with collection and condition filters. Select a collection to manage it or add items. Wide layouts use a filter sidebar; smaller windows scroll vertically. Controls use Cupertino on iOS/macOS, Material 3 on Android, and Fluent on Windows/Linux.

Data lives in the application support directory. Photo attachment copies bytes into app-owned `photos/` files; SQLite stores only relative paths. Removing photos/items/collections removes unreferenced copies after the database change. Canceling an editor removes its newly imported photos. Permissions are requested only by an explicit attachment action; all catalog workflows work without photos. Camera capture is offered on mobile; Windows uses the gallery file picker. No application network, account, or telemetry code is present.

Issue #7 still owns release packaging and icon provenance review. The existing `AppStore/icon.png` is preserved and wired into all Android, iOS, and Windows launcher sizes using `python3 tool/sync_icons.py` (Pillow required for this development tool only). Its original spark-media generation was not rerun or independently verified in this change; the icon/release issue remains open.

Milestones: M1 Flutter skeleton + Windows/Android CI → M2 domain + persistence → M3 item/collection workflow → M4 locations + stats → M5 platform-authentic adaptive UI → M6 backup/export → M7 Windows release workflow.

## Quickstart

```
flutter --version            # pinned 3.47.7 / Dart 3.13.5
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build windows --release   # Windows host or windows-latest CI
flutter build apk --debug         # Android SDK on x64 Linux CI
```

Host is ARM64 Linux; Windows compile requires Windows CI. Android build runs in x64 GitHub Actions container. iOS build requires a macOS runner and remains unverified until one is configured.

## Working rules

- Implement in Flutter (Windows + Android + iOS from one codebase); apps must run on phones, tablets, and desktop; Windows is the primary CI/release build and Android/iOS (incl. tablets) must keep compiling. No Unity, no native Swift/Xcode-only, no React Native, no Expo, no Kotlin Multiplatform, no .NET MAUI.
- Follow PLATFORM-AUTHENTIC UX: never ship Material look on iOS, Cupertino look on Android, or phone-style UI on Windows/macOS; this repo uses strategy A (platform-native adaptive widgets: Cupertino / Material 3 / Fluent via an AdaptiveScaffold-type layer) and per-platform golden/widget tests must keep passing for TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.windows.
- Preserve the identifier prefix: Android applicationId, iOS bundle ID, and MSIX/Windows identity must use com.infinityball.curiocase (Windows identity cominfinityball.curiocase); never introduce a different prefix.
- Maintain AppStore/description.txt as accurate listing copy and keep the real AppStore/icon.png generated via ~/.local/bin/spark-media (OpenAI Images) wired into every platform icon set; never substitute a placeholder or claim generation you did not verify; report blockers and leave the icon issue open. Icon brief: "analyze the repo and AppStore description to generate an icon that does not have any text or marketing, transparency, borders or corner radius. The image needs to be square, be edge-to-edge graphics and a modern colorful representation of the function provided by the app or game. If a logo or symbol is used, then there should be a gradient background or other abstract background behind the logo." (use ~/.local/bin/spark-media --project curio-case image --prompt "...").
- The packaging/release issue must deliver .github/workflows/release.yml that builds the Windows release on windows-latest for v* tags/manual dispatch and attaches it to a GitHub release; never log secret values. iOS TestFlight (secret names ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_TEAM_ID) and Play releases are later opt-in milestones.
