# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Animosaic Colors" (working title): a detailed cozy coloring app with cute Animosaic animals (style: `docs/coloring_refs/STYLE.md`). It uses Flutter + Flame and targets Android first, landscape only, on phones and tablets. The product plan, stages and acceptance criteria live in `PLAN.md` (Russian). Work one stage at a time and check that stage's «Готово, когда» criterion before moving on.

Current state: Stage 0 (project scaffold) is done, and the Stage 3 trial batch put 10 free pictures in `assets/coloring/free/`. Stage 1 (the coloring core) is implemented and tested: `/coloring/:id` opens a picture in the three modes, fills through the shader, saves the work and restores it. The Stage 1 checks that need a real weak phone (fill latency, 60 FPS, shader edges, haptics) are still pending. Settings, About, the parental gate and the paywall work with the fake test store. The «Architecture» section mixes what exists with the target from `PLAN.md`; update it as each part becomes real.

Android is the only platform. Bring another back with `flutter create --platforms=<name> .` when needed.

Sibling project: Animosaic puzzles at `../puzzles` (its own `CLAUDE.md` and `docs/PLAN.md`). The stack, theme, router, l10n, settings, parental gate and the `catalog`, `content` and `purchase`/`subscription` modules are **copied** from there. There is no shared package, so the two apps release independently. Read the puzzles code before writing a module the plan says to bring over.

Git: `main` is pushed to `git@github.com:qwddz/coloring.git` over SSH. Commit or push only when the user asks; no CI yet. Secrets (`.env`, keystores, `key.properties`) are gitignored.

## Commands

```bash
flutter pub get                                   # install dependencies
flutter gen-l10n                                  # regenerate lib/l10n/app_localizations*.dart from ARB files
flutter analyze                                   # must report "No issues found"
dart format lib test                              # format
flutter test                                      # all tests
flutter test test/features/content/               # one folder
flutter test --plain-name "<test name>"           # one test by name
flutter emulators --launch Medium_Phone_API_37.0  # phone emulator (20:9)
flutter emulators --launch Tablet_API_37          # tablet emulator (2560x1600, 16:10, Android 16+)
flutter devices                                   # list devices / emulators
flutter run -d <device-id>                        # run (fake store, bundled content only)
flutter run -d <device-id> --dart-define=CDN_BASE_URL=<url> --dart-define=REVENUECAT_API_KEY=<key>  # CDN content, real store
flutter run --profile -d <device-id>              # fill latency (<50 ms) and 60 FPS checks
flutter run --profile -d <device-id> --dart-define=COLORING_PERF_LOG=true      # log tap-to-pixels latency (`coloring.perf`, p50/p95 every 20 taps)
flutter run --profile -d <device-id> --dart-define=COLORING_PERF_OVERLAY=true  # performance overlay + FPS counter on the canvas
```

`flutter gen-l10n` reads `l10n.yaml`: ARB files in `lib/l10n/`, template `app_en.arb`, output `app_localizations.dart`, non-nullable getters. The generated `app_localizations*.dart` files are checked in next to the ARBs; regenerate after every ARB change. `flutter pub get` also regenerates them (`flutter: generate: true`).

The launcher icon is a placeholder (`assets/icon/`, made by `tools/icon/placeholder_icon.py`). After changing the art, run `FLUTTER_ROOT=/opt/homebrew/share/flutter /opt/homebrew/share/flutter/bin/dart run flutter_launcher_icons`.

Run the profile checks on a real low-end phone as well as the emulator, because shader performance on an emulator says little.

## Release build

The upload key lives outside the project folder, in `~/keys/coloring/` (create it like `../puzzles/CLAUDE.md` describes for `~/keys/puzzles`). Point `COLORING_KEY_PROPERTIES` at its `key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`):

```bash
COLORING_KEY_PROPERTIES=~/keys/coloring/key.properties flutter build appbundle --release \
  --build-number=$(date -u +%y%m%d%H) \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=CDN_BASE_URL=<cdn url> \
  --dart-define=REVENUECAT_API_KEY=$(grep '^REVENUECAT_GOOGLE_API_KEY=' .env | cut -d= -f2-) \
  --dart-define=REVIEW_CODE_SHA256=$(grep '^REVIEW_CODE=' .env | cut -d= -f2- | tr -cd 'A-Z0-9' | shasum -a 256 | cut -c1-64)
```

- Without `COLORING_KEY_PROPERTIES`, release builds are signed with the debug key (Gradle warns) and Google Play rejects them. A variable pointing at a missing or incomplete file stops the build.
- A release build without `CDN_BASE_URL` or a `goog_…` `REVENUECAT_API_KEY` stops at startup. Without `REVENUECAT_API_KEY`, debug builds and tests use `FakePurchaseService` (instant "test store", nothing charged) and never configure the RevenueCat SDK.
- `REVIEW_CODE_SHA256` enables "I have an access code" on the paywall for Google Play reviewers (`lib/features/subscription/data/review_access.dart`); without it the button is hidden.
- `versionCode` must grow with every upload: `--build-number` from the UTC date and hour. Keep `build/symbols` of every uploaded build to decode obfuscated traces.
- R8 (`isMinifyEnabled`, `isShrinkResources`) is on in `android/app/build.gradle.kts`; add `-keep` rules in `android/app/proguard-rules.pro` only if a release build crashes where debug does not.

## Architecture (target, from PLAN.md)

- `lib/main.dart` locks the orientation to landscape and wraps the app in `ProviderScope`.
- `lib/app/`: `ColoringApp` (`MaterialApp.router`), `routerProvider` (go_router, exposed through Riverpod), the «paper» theme (`BookPalette`, Nunito) with shared widgets, and `resolveAppLocale` (uk/en/ru: the first supported device language, else English, with a manual override in settings).
- Routes: `/` categories, `/category/:id` pictures, `/coloring/:id` the coloring screen (a locked picture redirects to the paywall), `/paywall?from=<pictureId>` the full version (opens `from` after the purchase, else goes back; asks the parental gate unless pushed with `paywallGatePassed`), `/settings`, `/about`.
- Settings (`settingsProvider`: sound, music, vibration, language) live in SharedPreferences, loaded in `main()` before the first frame. The coloring screen plays sounds (`lib/features/audio/`, `assets/audio/`) and vibrates through `coloringFeedbackProvider` when they are on; music is stored only.
- `lib/core/`: shared constants, utilities, logging, JSON file store.
- `lib/features/`: `catalog`, `coloring`, `palette`, `gallery` («Мои работы»), `progress`, `subscription`, `content`, `settings`.
- Menus, catalog, «Мои работы», paywall and settings are plain Flutter widgets. Flame is used only on the coloring screen via `GameWidget`.
- The coloring screen (`coloring_screen.dart`) shows the canvas (4:3) with the toolbar and palette (`lib/features/palette/`) beside it, in immersive sticky mode. `coloringControllerProvider(pictureId)` owns the picture, the `ColoringSession` and saving; it refuses locked pictures (the screen then replaces itself with the paywall). The controller drives `ColoringGame` (`game/`) through the pure-Dart `ColoringCanvasSink`, and `ColoringCanvas` reports taps, long presses and magic-brush strokes back through callbacks. The shader program comes from `fillRendererProvider`; widget tests override it with `FlatFillRenderer`.
- Coloring has no flood fill on the device. Each picture ships precomputed layers at 2048 × 1536:
  - `lines.png`: the outline, drawn on top of the fill.
  - `regions.png`: the region id in each pixel (R = high byte, G = low byte, 0 = line). It must be lossless, so never recompress or resize it.
  - `colored.webp`, `regions.json` (palette, plus each region's correct color, area, bbox, label point and radius) and `thumb.webp`.
- A tap looks up the region id in a `Uint16List` copy of `regions.png`. The fill state goes to the fragment shader `shaders/coloring.frag` as an opaque (N + 1) × 2 texture, one column per region id (column 0 unused): row 0 holds the display color (white when unfilled), row 1 the palette index (R) and a correct-color flag (G = 255). The shader samples region ids at texel centers. It also handles the fill "wave" animation and the number highlight.
- `lib/features/coloring/model/` is pure Dart with no Flame imports and is unit-tested. It covers: region lookup with tolerance for taps on lines, fill state, undo (50 steps), and the rules of the three modes (free, by numbers, magic brush).
- Each work is a JSON file in `<app documents>/works/` (`WorkRepository`, `lib/features/progress/`), with a PNG preview next to it (the preview comes with «Мои работы»):
  - The JSON holds the picture id, mode, region colors, modified time and a completed flag.
  - The JSON is saved after every fill and on app pause.
  - The preview is redrawn only when leaving the screen.
  - `<app documents>/progress.json` (`progressProvider`, `progress_store.dart`) holds the ids of completed pictures (the star) next to the works. It is written when a picture first completes and kept when a work is cleared or deleted; an unreadable file is never overwritten.
- Content comes from `assets/manifest.json` (`ContentManifest`: categories → `PictureEntry` with `level`, `characters`, `free`, `asset` or `url` + `sha256`), replaced at runtime by a newer valid manifest from the CDN (`lib/features/content/`, as in puzzles):
  - Free pictures are in `assets/coloring/free/<id>/` (declare the folder in `pubspec.yaml` once it exists).
  - Paid pictures are single zips from the CDN. `PictureStore.load` returns `PictureFiles` (read a layer by name): bundled assets as they are, or the zip downloaded once, checked by sha256, unpacked flat into `<app support>/pictures/<id>/` with the checksum stored next to the layers. A zip lacking `lines.png`, `regions.png`, `colored.webp` or `regions.json` is rejected as corrupt.
- Pictures are produced by `tools/coloring_pipeline/` (Python), using the style anchor `docs/coloring_refs/style_anchor.png` and the rows in `scenes.csv`. Generation costs money; the user runs it and makes the style decisions.

## Rules

- `catalog/`, `content/` and `subscription/` are ported from Animosaic. Change them only when necessary, and keep them close to the puzzles versions.
- State lives in Riverpod providers. Widgets render and forward events; no business logic goes in widgets.
- Keep user-facing strings out of code. Every string goes into `lib/l10n/app_en.arb` (template) plus `app_uk.arb` and `app_ru.arb`, then run `flutter gen-l10n`. Category and picture titles come from the manifest, keyed by id; code uses only ids.
- Unit tests are required for the region model (lookup, fill state, undo, mode rules) and for work/progress storage. The shader and region model are the riskiest parts, so test them on a real weak device, not only an emulator.
- Every access check goes through `canColor` / `canColorProvider(entry)` (`entry.free || fullAccess`; entitlement `full`, product `full_version` via RevenueCat). Locked pictures go through the parental gate before the paywall, and so do "Share" and any link out of the app (`openLinkThroughGate`). The `/coloring/:id` redirect only works once the manifest is loaded, so the Stage 1 coloring controller must refuse locked pictures too.
- Android: the activity is `sensorLandscape` and the application declares `android:appCategory="game"`; keep both when editing `AndroidManifest.xml`. Use immersive sticky mode on the coloring screen.
- Palette circles and buttons are at least 48 dp. A touch counts as a tap when it lasts less than 300 ms and moves less than 10 dp; anything else is a pan or zoom.
- No Firebase Analytics (Google Play Families policy); Crashlytics only.
- API keys (image generator, RevenueCat, CDN) go only in environment variables or `.env`, never in code or assets. The release keystore lives outside the project folder and is found through `COLORING_KEY_PROPERTIES` (see «Release build»).
- `applicationId` and `namespace` are `app.animosaic.coloring` (`MainActivity` in `android/app/src/main/kotlin/app/animosaic/coloring/`). Play Console and the `full_version` product get tied to it at the first upload, so don't change it after that.
- The Android launcher name is not in ARB: it lives in `android/app/src/main/res/values{,-uk,-ru}/strings.xml` (`app_name`).
- Privacy policy, terms and contact links are in `lib/features/settings/data/about_links.dart`; the `animosaic.app/colors/…` pages are placeholders to publish before the first upload.
