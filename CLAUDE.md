# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Animosaic Colors" (working title): a detailed cozy coloring app with cute Animosaic animals (style: `docs/coloring_refs/STYLE.md`). It uses Flutter + Flame and targets Android first, landscape only, on phones and tablets. The product plan, stages and acceptance criteria live in `PLAN.md` (Russian). Work one stage at a time and check that stage's «Готово, когда» criterion before moving on.

Current state: Stages 0, 1 and 2 are implemented and tested (unit and widget tests); Stage 3 is done (100 pictures: 30 free in `assets/coloring/free/`, 70 paid on the CDN; the AAB size was accepted). Stage 4 passed on the phone emulator (2026-11-23): a paid picture downloads once, reopens and continues offline, and a cache folder missing a layer is downloaded again. Stage 5: RevenueCat is configured (see «Rules»); the Play-side product, service account and licence-tester checks wait for the first upload. Stage 2: the catalog shows level badges, a star on completed pictures and a per-category counter; tapping a picture continues the latest unfinished work or opens the mode picker (free / by numbers / magic brush); «Мои работы» lists works with previews (continue, new coloring, save to gallery, gated share; no delete yet); the music switch is hidden until Stage 6. `minSdk` is 24 (Android 7). The checks that need a real weak phone (fill latency, 60 FPS, shader edges, haptics, export memory) are still pending. Stage 2b «Рисовалка» (`PLAN.md`): the first home tile opens `/draw`, a white 4:3 canvas; pencil, felt-tip, marker, eraser and rainbow are free, the other brushes, stamps, fill bucket and mirror need the full version; drawings autosave to `drawings/` and show in «Мои работы». A home category whose pictures are all paid shows a lock while there is no full access. The drawing weak-phone checks (60 FPS, undo ≤ 150 ms, fill ≤ 300 ms, memory over 300 strokes) are pending too. Settings, About, the parental gate and the paywall work with the fake test store. The «Architecture» section mixes what exists with the target from `PLAN.md`; update it as each part becomes real.

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
flutter run -d <device-id> --dart-define=CDN_BASE_URL=https://cdn.animosaic.app/colors --dart-define=REVENUECAT_API_KEY=<key>  # CDN content, real store
flutter run --profile -d <device-id>              # fill latency (<50 ms) and 60 FPS checks
flutter run --profile -d <device-id> --dart-define=COLORING_PERF_LOG=true      # log tap-to-pixels latency (`coloring.perf`, p50/p95 every 20 taps)
flutter run --profile -d <device-id> --dart-define=COLORING_PERF_OVERLAY=true  # performance overlay + FPS counter on the canvas
```

`flutter gen-l10n` reads `l10n.yaml`: ARB files in `lib/l10n/`, template `app_en.arb`, output `app_localizations.dart`, non-nullable getters. The generated `app_localizations*.dart` files are checked in next to the ARBs; regenerate after every ARB change. `flutter pub get` also regenerates them (`flutter: generate: true`).

The launcher icon (`assets/icon/`) is made from the store icon `tools/store/icons/fox_brush2_b.png` (Gemini, `tools/store/icon_candidates.py`) by `tools/icon/app_icon.py`; the store graphics live in `tools/store/listing/` (`tools/store/feature_graphic.py`). After changing the art, run `FLUTTER_ROOT=/opt/homebrew/share/flutter /opt/homebrew/share/flutter/bin/dart run flutter_launcher_icons`.

Run the profile checks on a real low-end phone as well as the emulator, because shader performance on an emulator says little.

## Release build

The upload key lives outside the project folder, in `~/keys/coloring/` (create it like `../puzzles/CLAUDE.md` describes for `~/keys/puzzles`). Point `COLORING_KEY_PROPERTIES` at its `key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`):

```bash
COLORING_KEY_PROPERTIES=~/keys/coloring/key.properties flutter build appbundle --release \
  --build-number=$(date -u +%y%m%d%H) \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=CDN_BASE_URL=https://cdn.animosaic.app/colors \
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
- Routes: `/` categories, `/category/:id` pictures, `/works` «Мои работы», `/coloring/:id` the coloring screen (a locked picture redirects to the paywall), with `?work=<workId>` to open that work or `?mode=<free|numbers|magic>` to start a new work in that mode (`ColoringRequest`, `coloring_route.dart`; `workId` wins; neither means the latest work), `/paywall?from=<pictureId>` the full version (after the purchase it goes through `openPictureFlow`: continue the latest unfinished work or show the mode picker; else goes back; asks the parental gate unless pushed with `paywallGatePassed`), `/settings`, `/about`, `/draw` the drawing screen: plain = the latest drawing or a new one, `?work=<drawingId>` that drawing, `?new=<drawingId>` a new sheet with an id generated at navigation (`DrawingRequest`, `drawRoute`, `drawing_route.dart`); not gated, only tools are.
- Settings (`settingsProvider`: sound, music, vibration, language) live in SharedPreferences, loaded in `main()` before the first frame. The coloring screen plays sounds (`lib/features/audio/`, `assets/audio/`) and vibrates through `coloringFeedbackProvider` when they are on; music is stored only and its switch is hidden in settings (`showMusicSetting`) until Stage 6.
- `lib/core/`: shared constants, utilities, logging, JSON file store.
- `lib/features/`: `catalog`, `coloring`, `palette`, `gallery` («Мои работы»), `progress`, `subscription`, `content`, `settings`, `drawing`.
- Menus, catalog, «Мои работы», paywall and settings are plain Flutter widgets. Flame is used only on the coloring screen via `GameWidget`; the drawing screen is a plain `CustomPaint`.
- The coloring screen (`coloring_screen.dart`) shows the canvas (4:3) with the toolbar and palette (`lib/features/palette/`) beside it, in immersive sticky mode. `coloringControllerProvider(ColoringRequest)` owns the picture, the `ColoringSession` and saving; it refuses locked pictures (the screen then replaces itself with the paywall). The controller drives `ColoringGame` (`game/`) through the pure-Dart `ColoringCanvasSink`, and `ColoringCanvas` reports taps, long presses and magic-brush strokes back through callbacks. The shader program comes from `fillRendererProvider`; widget tests override it with `FlatFillRenderer`.
- Coloring has no flood fill on the device (the drawing canvas has its own raster fill, below). Each picture ships precomputed layers at 2048 × 1536:
  - `lines.png`: the outline, drawn on top of the fill.
  - `regions.png`: the region id in each pixel (R = high byte, G = low byte, 0 = line). It must be lossless, so never recompress or resize it.
  - `colored.webp`, `regions.json` (palette, plus each region's correct color, area, bbox, label point and radius) and `thumb.webp`.
- A tap looks up the region id in a `Uint16List` copy of `regions.png`. The fill state goes to the fragment shader `shaders/coloring.frag` as an opaque (N + 1) × 2 texture, one column per region id (column 0 unused): row 0 holds the display color (white when unfilled), row 1 the palette index (R) and a correct-color flag (G = 255). The shader samples region ids at texel centers. It also handles the fill "wave" animation and the number highlight.
- `lib/features/coloring/model/` is pure Dart with no Flame imports and is unit-tested. It covers: region lookup with tolerance for taps on lines, fill state, undo (50 steps), and the rules of the three modes (free, by numbers, magic brush).
- Drawing (`lib/features/drawing/`): a fixed `drawingCanvasWidth × drawingCanvasHeight` (2048 × 1536, kept after the emulator spike in `.omc/research/drawing-spike.md`; if a real tablet fails the undo check, lower the checkpoint interval before shrinking the canvas) white canvas.
  - `model/` is pure Dart and unit-tested: tools and `BrushSpec`, deterministic seeded dabs, left-right mirror, scanline flood fill (sum RGB distance ≤ 32, 1 px dilation into antialiased edges only, run in `Isolate.run`), `DrawingHistory` (30 undo steps, a checkpoint every 10 ops (`defaultCheckpointEvery`), ≤ 4 checkpoint images, replay ≤ 9 ops; the committed image is flattened every 10 commits), `DrawGestureClassifier`.
  - `render/composeStroke` is the one drawing function for live, commit and replay: `drawAtlas` over generated sprites inside a bounded `saveLayer`; fills replay from their RLE runs with `drawVertices`, no per-op images. Commits use `toImageSync` and are flattened with `await toImage` every few commits.
  - The live stroke repaints from a `ChangeNotifier`, never from Riverpod state. `drawingControllerProvider(DrawingRequest)` owns the engine, the op queue and saving; paid tool selection awaits the first `fullAccessProvider` value.
- Each work is a JSON file in `<app documents>/works/` (`WorkRepository`, `lib/features/progress/`), with a PNG preview next to it, `works/<workId>.p<sourceModifiedMillis>.png` (640 × 480, `WorkPreviewService`):
  - The JSON holds the picture id, mode, region colors, modified time and a completed flag.
  - The JSON is saved after every fill and on app pause.
  - The preview is redrawn when leaving the screen and on app pause (not on every fill). Missing or stale previews of bundled pictures are backfilled when «Мои работы» opens. Staleness compares the work's modified time stored in the file name with the work's `modified`, never file times.
  - `<app documents>/progress.json` (`progressProvider`, `progress_store.dart`) holds the ids of completed pictures (the star) next to the works. It is written when a picture first completes and kept when a work is cleared (and, once deleting works exists, when one is deleted); an unreadable file is never overwritten.
- Drawings live in `<app documents>/drawings/` (`DrawingRepository`): `<id>.json` (`DrawingRecord` v1), the raster `<id>.r<modifiedMillis>.png` (written before the JSON; other rasters of the id, orphans and `.tmp` files are cleaned up) and the preview `<id>.p<sourceModifiedMillis>.png` (640 × 480). `save(record, pngFuture)` is queued synchronously and every read awaits pending saves. Saved 2 s after an op, on pause, on leave and before a new sheet; an empty sheet is never written. «Мои работы» merges works and drawings (`galleryItemsProvider`).
- Content comes from `assets/manifest.json` (`ContentManifest`: categories → `PictureEntry` with `level`, `characters`, `free`, `asset` or `url` + `sha256`), replaced at runtime by a newer valid manifest from the CDN (`lib/features/content/`, as in puzzles):
  - Free pictures are in `assets/coloring/free/<id>/` (declare the folder in `pubspec.yaml` once it exists).
  - Paid pictures are single zips from the CDN. `PictureStore.load` returns `PictureFiles` (read a layer by name): bundled assets as they are, or the zip downloaded once, checked by sha256, unpacked flat into `<app support>/pictures/<id>/` with the checksum stored next to the layers. A zip lacking `lines.png`, `regions.png`, `colored.webp` or `regions.json` is rejected as corrupt.
- Pictures are produced by `tools/coloring_pipeline/` (Python), using the style anchor `docs/coloring_refs/style_anchor.png` and the rows in `scenes.csv`. Generation costs money; the user runs it and makes the style decisions.

## Rules

- `catalog/`, `content/` and `subscription/` are ported from Animosaic. Change them only when necessary, and keep them close to the puzzles versions.
- State lives in Riverpod providers. Widgets render and forward events; no business logic goes in widgets.
- Keep user-facing strings out of code. Every string goes into `lib/l10n/app_en.arb` (template) plus `app_uk.arb` and `app_ru.arb`, then run `flutter gen-l10n`. Category and picture titles come from the manifest, keyed by id; code uses only ids.
- Unit tests are required for the region model (lookup, fill state, undo, mode rules) and for work/progress storage, and for the drawing model (dabs, flood fill, history, gestures) and drawing storage. The shader and region model are the riskiest parts, so test them on a real weak device, not only an emulator.
- Every access check goes through `canColor` / `canColorProvider(entry)` (`entry.free || fullAccess`; entitlement `full`, product `full_version` via RevenueCat). Locked pictures go through the parental gate before the paywall, and so do "Share" and any link out of the app (`openLinkThroughGate`). The `/coloring/:id` redirect only works once the manifest is loaded, so the Stage 1 coloring controller must refuse locked pictures too. Drawing tools use `canUseTool` (`tool.isFree || fullAccess`; free: pencil, felt, marker, eraser, rainbow) through the controller, which awaits the first access value; `canUseToolProvider` only draws badges. A locked tool goes through `openPaywallThroughGate`. A home category is locked (badge only) when none of its pictures passes `canColor` (`isCategoryLocked`).
- Android: the activity is `sensorLandscape` and the application declares `android:appCategory="game"`; keep both when editing `AndroidManifest.xml`. Also keep `WRITE_EXTERNAL_STORAGE` with `maxSdkVersion="29"` and `android:requestLegacyExternalStorage="true"` (gallery save on Android 7–10 through `gal`); there are no `READ_*` / `READ_MEDIA_*` permissions and no `AD_ID`. Android 11+ saves through MediaStore with no permission. Auto Backup stays on (`allowBackup` default) but excludes `app_flutter/drawings/` (`res/xml/backup_rules.xml`, `data_extraction_rules.xml`): the 25 MB quota would otherwise switch off the whole backup. Use immersive sticky mode on the coloring and drawing screens (shared counter in `lib/app/immersive_mode.dart`). Both canvases are wrapped in `BackGestureExclusion` (`lib/app/back_gesture_exclusion.dart`), which sends their rects over the `app.animosaic.coloring/gestures` channel to `MainActivity` (`systemGestureExclusionRects`, Android 10+), so a stroke from the canvas edge draws instead of triggering the system back gesture; keep the handler when editing `MainActivity.kt`.
- Palette circles and buttons are at least 48 dp. A touch counts as a tap when it lasts less than 300 ms and moves less than 10 dp; anything else is a pan or zoom. Exception: on the drawing canvas one finger or a stylus draws from the first contact; a second finger discards a short stroke (< 10 dp or < 250 ms) or commits a longer one, then zooms. Touches during a stylus contact and 300 ms after it are ignored.
- No Firebase Analytics (Google Play Families policy); Crashlytics only.
- RevenueCat project «Animosaic Colors» (`proj94119f87`, separate from puzzles; the Play app has the Google Play service account JSON, the same key as puzzles): entitlement `full` (the only one the app checks) ← products `full_version` (Google Play app `app.animosaic.coloring`, `app92f5f98d7d`) and `lifetime` (Test Store); offering `default` (current) with package `$rc_lifetime` holding both. Keys in `.env`: `REVENUECAT_GOOGLE_API_KEY` (goog_, release builds), `REVENUECAT_API_KEY` (test_, Test Store for debug; its purchases persist across restarts, unlike `FakePurchaseService`), `REVENUECAT_SECRET_KEY` (sk_, API v2 for configuration only; never pass it to a build). The auto-created entitlement `animosaic_app_pro` is unused.
- API keys (image generator, RevenueCat, CDN) go only in environment variables or `.env`, never in code or assets. The release keystore lives outside the project folder and is found through `COLORING_KEY_PROPERTIES` (see «Release build»).
- `applicationId` and `namespace` are `app.animosaic.coloring` (`MainActivity` in `android/app/src/main/kotlin/app/animosaic/coloring/`). Play Console and the `full_version` product get tied to it at the first upload, so don't change it after that.
- The Android launcher name is not in ARB: it lives in `android/app/src/main/res/values{,-uk,-ru}/strings.xml` (`app_name`).
- Privacy policy, terms and contact links are in `lib/features/settings/data/about_links.dart`; the `animosaic.app/colors/…` pages are placeholders to publish before the first upload.
