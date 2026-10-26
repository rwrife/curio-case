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

Scaffold only: documentation, toolchain contract, and the generated store icon (`AppStore/icon.png`, 1024x1024 RGB via OpenAI Images `gpt-image-2.5-flare` through spark-media). No Flutter project, CI, or app code exists yet — that is issue #1.

Milestones: M1 Flutter skeleton + Windows/Android CI → M2 domain + persistence → M3 item/collection workflow → M4 locations + stats → M5 platform-authentic adaptive UI → M6 backup/export → M7 Windows release workflow.

## Quickstart (planned)

```
flutter --version            # pinned 3.47.7 / Dart 3.13.5
flutter create . --platforms=windows,android,ios   # issue #1 generates the skeleton
flutter test
flutter build windows --release
flutter build apk --debug    # Linux Docker lane
```
