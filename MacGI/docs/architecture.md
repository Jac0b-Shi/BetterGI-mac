# betterGI-mac Architecture

## Current Stage

This repository implements a SwiftUI/AppKit BetterGI shell plus the first native execution-chain pieces: real window enumeration, capture providers, guarded input dispatch, PaddleOCR, template-recognition models, YOLO model/postprocess scaffolding, runtime resource roots, and Rust FFI fallback wiring.

See [porting-inventory.md](./porting-inventory.md) for the complete upstream BetterGI component catalog and macOS porting priority matrix.

## Layers

### Swift Shell

Responsibilities:

- Main macOS window.
- Menu bar entry.
- HUD `NSPanel`.
- User-facing settings and status.
- Permission surfaces.
- Capture/input/core service boundaries.

Key files:

- `Sources/MacGI/App/MacGIApp.swift`
- `Sources/MacGI/App/AppState.swift`
- `Sources/MacGI/App/HUDPanelController.swift`
- `Sources/MacGI/Views`
- `Sources/MacGI/Components`

Detailed BetterGI page replicas currently live in:

- `Sources/MacGI/Views/Pages/OverviewPage.swift`
- `Sources/MacGI/Views/Pages/FeaturesPage.swift`
- `Sources/MacGI/Views/Pages/WorkflowPages.swift`
- `Sources/MacGI/Views/Pages/SettingsPage.swift`

`WorkflowPages.swift` holds source-derived mock replicas for 一条龙, 调度器, JS 脚本, 地图追踪, 录制回放, 辅助操控, 快捷键, and 通知. These views are intentionally more detailed than the screenshot references because their structure is derived from upstream XAML.

### AppState

`AppState` is the single UI state source. Pages and HUD read from it, and actions mutate it through explicit methods.

Important state:

- `appStatus`
- `gameWindowStatus`
- `captureStatus`
- `inputStatus`
- `coreStatus`
- `features`
- `recentLogs`
- `debugConfidence`
- `captureFPS`
- `frameSize`
- overlay toggles such as `showOverlayLogBox`, `showOverlayStatus`, `showOverlayMetrics`, `showOverlayDirections`, `overlayUidCoverEnabled`, and `overlayLayoutEditEnabled`

### Mock Services

`MockCoreBridge`, `MockCaptureService`, `MockInputService`, and `MockGameWindowTracker` remain as fallbacks and UI fixtures. Runtime paths now go through typed services such as `ScreenCaptureKitFrameProvider`, `CGEventInputDispatcher`, and `RustCoreBridge`; UI pages should still call `AppState` methods instead of invoking those low-level APIs directly.

Workflow pages should continue to introduce runtime data through typed model objects before UI binding. The scheduler page now reads a Swift mirror of BetterGI `ScriptGroup` / `ScriptGroupProject` and can route enabled `Javascript` projects into `BGIJSScriptTaskExecutor`, `KeyMouse` projects into the BGI recorder-compatible macro playback bridge, `Shell` projects into the BGI `ShellTask`-compatible macOS shell executor, and `Pathing` projects into the BGI `PathingTask.BuildFromFilePath` / `PathExecutor.Pathing`-compatible loader and navigation-backend skeleton; hotkeys and notification providers should follow the same model-first pattern before deeper UI work.

Pathing projects now construct `BGIRealPathingNavigationBackend` from `AppState`, using the selected `WindowInfo` for capture, input safety, mini-map localization, camera rotation, and big-map teleport clicks. When the loaded Rust core dylib exposes the `big-map-sift` ABI and `Assets/Map/Teyvat/Teyvat_0_256_SIFT.*` exists, `AppState` now prefers `BGIBigMapSiftPositionProvider` for big-map center recognition; if SIFT matching is unavailable or returns no match, it falls back to the existing mini-map localization provider so current pathing remains usable. `BGIBigMapInteractionService` derives its screen-coordinate capture rectangle from the current target window instead of assuming a fixed 1920x1080 full-screen game, so windowed YAAGL/Wine captures and future title-bar handling remain centralized in `WindowInfo` / capture extraction. The backend is still a first-layer port: full `TpTask` big-map verification, nearest teleport lookup, action handlers, and OpenCV-backed `ImageRegion` details remain pending.

JS `genshin.*` commands follow the same safe progression as JS input. `BGIJSScriptRunner` records typed `BGIJSScriptGenshinCommand` values during synchronous JavaScriptCore execution, and `AppState` replays the subset that is safe to execute after the script returns. The bridge exposes the real script-facing names currently seen in migrated `User/JsScript`, including lower-case metric properties, `getPositionFromMapWithMatchingMethod(...)`, `returnMainUi()`, and `tpToStatueOfTheSeven()`. The current replayer executes `genshin.Tp(x, y, mapName, true)` through `BGIBigMapInteractionService`, executes `genshin.SetBigMapZoomLevel(level)` through the same big-map service using upstream slider geometry, and can execute `genshin.MoveMapTo(...)` / `MoveIndependentMapTo(...)` when a big-map center-position provider is available; without that provider they remain pending because upstream SIFT/feature `GetPositionFromBigMap` is not ported yet. It also executes `genshin.ReturnMainUi()` / `returnMainUi()` through a first-layer `BGIReturnMainUIService`, executes `genshin.ChooseTalkOption(text, skipTimes, isOrange)` through `BGIChooseTalkOptionService`, executes `genshin.SetTime(hour, minute, skip)` through `BGISetTimeService`, executes `genshin.Relogin()` through `BGIExitAndReloginService`, and has first-layer `SwitchParty` / `AutoFishing` services for their currently ported UI branches. `ChooseTalkOption` mirrors the first branch of upstream `ChooseTalkOptionTask.SingleSelectText`: it first waits for `Bv.WaitAndSkipForTalkUi` by matching `AutoSkip.DisabledUiButtonRo`, then finds `AutoSkip.OptionIconRo`, derives the right-side OCR text area from the lowest option bubble, presses Space while options are absent, clicks the OCR line containing the requested text, and applies the same HSV orange-text threshold when `isOrange` is requested. `SetTime` mirrors the first-layer upstream `SetTimeTask`: it returns to the main UI, opens the Paimon menu, clicks the 1080p time entry, uses the same clock center/radius/angle formula for three small clicks plus one drag, confirms, optionally sends the skip-animation clicks, and waits for `Common.Element.PageCloseWhiteRo` before returning to main UI when capture is available. `Relogin` mirrors upstream `ExitAndReloginJob`'s first-layer UI loop with AutoWood menu/confirm/enter-game templates and the same retry counts and 1080p click points; third-party login handling still needs a dedicated macOS path. Non-forced teleport and `TpToStatueOfTheSeven` remain pending because upstream `TpTask.TpOnce` still depends on `GetBigMapRect`, SIFT/feature `GetPositionFromBigMap`, region switching, and viewport-relative click conversion; loading `tp.json` nearest-point data alone is not enough to mark them executable. This is deliberately record-then-replay, not yet upstream's immediate async ClearScript semantics; `ChooseTalkOption` still needs full AutoSkip option branches and voice-wait behavior, and `SetTime`/`Relogin` still need real-window calibration for YAAGL menu and login timing.

Big-map UI status now has a dedicated first-layer recognizer aligned with upstream `BvStatus`: `BGIGameUIStatusRecognizer` matches QuickTeleport `MapScaleButton`, `MapSettingsButton`, and `MapUndergroundSwitchButton` templates for `IsInBigMapUi`, and the Common/Element `PaimonMenu` template for the first layer of `IsInMainUi`. The recognizer keeps upstream `Bv.GetBigMapScale`'s internal slider fraction from the scale-button center Y with `TpConfig.ZoomStartY = 468` and `ZoomEndY = 612`, while `BGICapturingJSScriptHostEnvironment` exposes upstream-compatible `genshin.GetBigMapZoomLevel()` as `(-5 * scale) + 6`, i.e. the script-facing 1.0...6.0 zoom level. `BGIBigMapInteractionService.setBigMapZoomLevel(_:)` mirrors upstream `TpTask.AdjustMapZoomLevel(double,double)`: it opens/verifies the big-map UI, reads the current zoom level from the slider, then drags `ZoomButtonX = 47` from the computed current Y to `468 + (612 - 468) * (targetLevel - 1) / 5`. `BGIBigMapInteractionService.moveMapTo(...)` now mirrors the first-layer upstream `TpTask.MoveMapTo` movement loop when supplied with a center-position provider: it opens/verifies the big map, reads current zoom, computes mouse distance from genshin-map coordinate offset with `MapScaleFactor`, performs upstream zoom-out/zoom-in decisions, distributes `MouseMoveMap` steps with the same cosine `GenerateSteps` algorithm, and uses upstream-style inertial prediction when a later center recognition fails. `BGIBigMapSiftPositionProvider` is the first production provider for that center hook: it registers BetterGI `Teyvat_0_256_SIFT.kp.bin` + `.mat.png` into the Rust `big-map-sift` bridge, matches the current grayscale big-map capture, converts the returned 256-scale map rect center to 2048-scale scene image coordinates, then uses `BGISceneMapCoordinateConverter.imageToGenshin`. `BGIBigMapInteractionService.openBigMap()` also follows upstream `TpTask.TryToOpenBigMapUi`: when a capture provider is available, it checks whether the current frame is already in the big-map UI before pressing the map hotkey, then verifies after opening. This prevents forced teleport replay/pathing from closing the map when the user or a previous task already has it open. After clicking a target coordinate, the service now mirrors the first branches of upstream `ClickTpPoint`: it looks for QuickTeleport `GoTeleport` and clicks the visible teleport button, reports the point as not activated when `MapCloseButton` is visible without a teleport button, or detects the QuickTeleport map-choice icon list and scans candidate rows from top to bottom, including multiple rows that use the same icon template. With an OCR provider, map-choice rows are filtered through an upstream-style `ColorRangeAndOcr` object covering the icon's right-side 200 px text region with non-HDR white text thresholds; empty or single-character OCR results are skipped before clicking. In the map-choice branch it also mirrors upstream `WaitForElementDisappear`: after clicking the teleport button it keeps rechecking the button and retry-clicking while the button remains visible. After the teleport click, the service mirrors upstream `WaitForTeleportCompletion` by polling captures until `PaimonMenu` indicates the main UI, excluding upstream-style revive prompts when an OCR provider is available by checking AutoFight `ConfirmRa` plus upper-half OCR for `复苏`/`Revive`, and retry-clicking `GoTeleport` if the button is still visible; timeout remains non-throwing like upstream. The interact key remains a fallback when capture is not wired or no branch is recognized. This only proves the big-map UI, upstream 1.0...6.0 zoom-level read/write, injected-center `MoveMapTo` drag loop, SIFT provider wiring and coordinate conversion, visible teleport-confirm-button, close-button invalid-point, map-choice row scanning, non-HDR map-choice OCR filtering, same-icon multi-match rows, map-choice-button-disappear retry path, Paimon-based main-UI teleport completion polling, and OCR-backed revive-prompt exclusion; full `TpTask.GetBigMapRect`, country/area switching before map movement, HDR-specific map-choice OCR thresholds, and complete nearest-teleport flow are still separate pending work.

### Runtime Resources

BetterGI ships large assets through packages such as `BetterGI.Assets.Model` and `BetterGI.Assets.Map`, while scripts are pulled from `bettergi-scripts-list` at runtime. The macOS port supports both compiled SwiftPM resources and first-launch downloaded resources:

- `Bundle.module/Resources/...` for assets already embedded in the app bundle.
- `~/Library/Application Support/betterGI-mac/Assets/...` for downloaded model/map/other packages with the same upstream layout.
- `~/Library/Application Support/betterGI-mac/User/...` for user scripts, pathing, combat strategies, TCG scripts, and subscriptions.
- `~/Library/Application Support/betterGI-mac/Repos/...` for shallow-cloned script repositories.
- `~/Library/Application Support/betterGI-mac/Cache/Downloads/...` for first-launch package archives fetched from NuGet/release mirrors.
- `~/Library/Application Support/betterGI-mac/Cache/Model/...` for optimized ONNX/runtime caches.

`BGIRuntimeResourceStore` owns the directory skeleton. `BGIExternalResourceURLFetcher` downloads or copies package archives into `Cache/Downloads`, and `BGIExternalResourceBootstrapper` checks coverage before invoking `BGIExternalResourceInstaller`. The installer consumes `.nupkg`/zip archives or expanded `contentFiles/any/any` directories and places files into the runtime skeleton. `BGIModelAssetResolver` checks runtime roots before falling back to `Bundle.module`, so first-launch downloads can provide `Assets/Model/Fish/bgi_fish.onnx` or map tiles under Application Support without changing predictor code.

The runtime store is symlink-aware. `~/Library/Application Support/betterGI-mac` can point to another volume such as `/Volumes/Data/Library/Application Support/betterGI-mac`, and user script folders such as `User/JsScript` may also be symlinks. Directory creation follows those links, script checkout preserves the symlink and replaces contents inside the resolved target directory, and JS `saved_files` restore keeps saved directory symlinks as links instead of expanding them into ordinary folders.

`BGIUserScriptCatalogLoader` scans the already-installed BetterGI `User` tree as a first-class runtime input, not just freshly checked-out repository content. The compatibility target is a Windows BetterGI user folder copied into `~/Library/Application Support/betterGI-mac/User`, including `JsScript`, `AutoPathing`, `AutoFight`, `AutoGeniusInvokation`, `KeyMouseScript`, `ScriptGroup`, `OneDragon`, `Temp`, and `Cache/MemoryFileCache`. The loader reads JS manifests/settings, builds an upstream-style `FileTreeNodeHelper.LoadDirectory` pathing tree without decoding all route JSON files, preserves nested combat/TCG strategy relative names such as `群友分享/...`, lists one-dragon/key-mouse/scheduler JSON configs, and decodes scheduler groups for UI/runtime binding. The local `User/ScriptGroup/狗粮+锄地.json` file is the current high-value scheduler compatibility sample because it chains multiple JS projects with non-default `jsScriptSettingsObject` payloads.

`AppState` loads `User/ScriptGroup/*.json` through that catalog at startup and exposes the loaded groups to `SchedulerPage`; if no real groups are present it falls back to the mock default group. The scheduler sidebar now reflects real group names and updates the selected group, and the normal run action follows upstream `OnStartScriptGroupAsync()` semantics by running only the selected group instead of all configured groups.

`BGIScriptRepositoryUpdater` mirrors upstream `ScriptRepoUpdater` at the repository-distribution layer. It uses `/usr/bin/git` to shallow-clone or fetch the `release` branch from the upstream CNB/GitCode/GitHub channels into `Repos/bettergi-scripts-list`, validates `repo.json` plus `repo/js`, `repo/pathing`, `repo/combat`, and `repo/tcg`, generates `repo_updated.json` by comparing the new index with the previous `repo_updated.json` or `repo.json`, and maps checked-out paths into `User/JsScript`, `User/AutoPathing`, `User/AutoFight`, and `User/AutoGeniusInvokation`.

`BGIScriptRepositoryCatalogLoader` parses the cloned repository into typed metadata before UI or runtime binding. It flattens the recursive `repo.json` `indexes` tree, decodes JS `manifest.json` fields such as `bgi_version`, `settings_ui`, `saved_files`, `library`, and `http_allowed_urls`, and decodes `settings.json` items for future SwiftUI settings controls. A smoke test parses the real local `bettergi-scripts-list` checkout when present.

`BGIScriptRepositoryUpdateMarkerGenerator` preserves the BetterGI WebView update-hint semantics. It calculates repository overlap from directory paths to avoid inheriting update flags across unrelated repositories, carries forward existing `hasUpdate` markers, marks nodes with newer `lastUpdated` timestamps or newly added paths, and bubbles leaf updates to their parents while refreshing the parent `lastUpdated` when appropriate.

`BGIScriptSubscriptionStore` mirrors the upstream repo-scoped subscription file behavior. It reads and writes `User/Subscriptions/{repoName}.json`, treats broken or empty files as no subscriptions, decodes `bettergi://script?import=` payloads as base64 then URL-decoded JSON path arrays, expands bare top-level subscriptions such as `js` into direct repository children before checkout, and compresses fully subscribed child sets back to parent paths. Subscribed-script updates can optionally refresh the central Git repository first, then checkout existing subscribed paths through the same symlink-preserving updater.

JS script checkout preserves user data declared by the upstream `manifest.json` `saved_files` field. Before replacing a JS script directory, `BGIScriptRepositoryUpdater` backs matching saved files or folders into `User/Temp/js/...`, restores them after checkout without dereferencing saved directory symlinks, then scans local JS imports/requires for `packages/...` references and copies those dependencies from the repository root into the script's local `packages/` folder, including package-internal relative JS imports.

`BGIJSScriptRunner` is the first macOS runtime layer for checked-out JS scripts. It loads installed projects from `User/JsScript/{folder}`, validates `manifest.json`, uses a PackageDocumentLoader-style resolver for `library`, `.` and `./packages`, rewrites BetterGI package/resource imports, evaluates transformed CommonJS-style modules on JavaScriptCore, injects `settings`, and exposes the upstream global host shape (`log`, `file`, input globals, `RecognitionObject`, `captureGameRegion()`, `BvPage`/`BvLocator`, `BvImage`, and a first `genshin.*` bridge). Host calls flow through `BGIJSScriptHostEnvironment`: the default environment records typed input, capture, empty OCR/template results, and typed `genshin.*` commands/results for tests; `BGIInputDispatchingJSScriptHostEnvironment` can translate supported JS input commands to the existing `InputAction`/`CGEventInputDispatcher` path for a known target window; and `BGICapturingJSScriptHostEnvironment` can inject a `CaptureImageFrame` provider plus OCR/template/recognition-object providers so scripts can call `captureGameRegion().Ocr()`, `captureGameRegion().Find(...)`, `captureGameRegion().FindMulti(...)`, `RecognitionObject.Ocr(...)`, `RecognitionObject.OcrMatch(...)`, `RecognitionObject.ColorRangeAndOcr(...)`, `new BvPage().Keyboard.KeyPress(...)`, `new BvPage().Mouse.VerticalScroll(...)`, `new BvPage().Ocr(rect)`, `GetByText(text, rect).FindAll()`, `WaitFor()` / `TryWaitFor()` / `WaitForDisappear()`, `Click(timeout)`, chain `WithRoi()` / `WithTimeout()` / `WithRetryInterval()` / `WithRetryAction()`, or `GetByImage(new BvImage(template, rect, threshold)).FindAll()` and receive BGI-style region dictionaries with `IsExist` / `IsEmpty` / `Click` / `DoubleClick` helpers. `OcrMatch` applies the upstream-style combined-text matching rules for `AllContainMatchText`, `OneContainMatchText`, `RegexMatchText`, and `ReplaceDictionary`; `ColorRangeAndOcr` now reaches the object-level provider so `PaddleOCRRecognitionEngine` can apply the same color-range OCR path outside direct trigger code. `ImageRegion.Find` and `FindMulti` now enforce upstream `ImageRegion.cs` support: `Find` allows template/OCR/OcrMatch/ColorRangeAndOcr, `FindMulti` allows template/OCR, and unsupported `ColorMatch`, `Detect`, or multi-target OCR-match/color-range requests fail instead of silently returning empty regions. For OCR shape, `Find(Ocr)` returns the ROI or full region with combined whitespace-stripped text, while `FindMulti(Ocr)` returns each OCR text box and applies `ReplaceDictionary`; text filtering remains a `BvLocator` responsibility, matching upstream. `BvLocator.FindAll` also follows upstream by resolving `BvImage` templates through single-target `ImageRegion.Find`, while direct `captureGameRegion().FindMulti(new BvImage(...))` remains the multi-template ImageRegion path. `ClickUntilDisappears(timeout)` now mirrors upstream by using the timeout only for the initial click and waiting for disappearance through a fresh locator with default wait settings and a retry click action. `BGIJSScriptTaskExecutor` is the task-level wrapper over this runtime: it loads installed scripts from `User/JsScript/{folder}`, builds a capturing host with OCR/template/object providers, updates game metrics from captured frames, and can optionally route supported JS input commands to `CGEventInputDispatcher` for a target window. App-layer JS execution prepares a real or mock capture frame, uses PaddleOCR when available, records the execution result, logs script output, replays recorded JS input through the existing `InputSafetyGate` path, sends recorded `genshin.Tp(..., force: true)` and `SetBigMapZoomLevel(level)` commands through the same guarded big-map service, can send recorded `MoveMapTo` / `MoveIndependentMapTo` commands when a big-map center-position provider is available, sends recorded `ReturnMainUi` commands through `BGIReturnMainUIService`, sends recorded `ChooseTalkOption` commands through `BGIChooseTalkOptionService` with OCR-backed text matching and upstream-style orange option filtering, sends recorded `SetTime` commands through `BGISetTimeService` with upstream clock input geometry, and sends recorded `Relogin` commands through `BGIExitAndReloginService` with AutoWood menu/confirm/enter-game templates. The scheduler layer now binds JS, KeyMouse, Shell, and Pathing projects through the same upstream `ScriptGroupProject` / `RunMulti` model; Pathing has the upstream stage order represented through `BGIPathExecutor` and a first real `BGIRealPathingNavigationBackend` that uses mini-map localization, camera rotation, guarded input, and target-window big-map clicks. The `genshin.*` bridge now carries upstream-style properties (`Width`, `Height`, `ScaleTo1080PRatio`, `ScreenDpiScale`), overloaded parameters, bool/int/double/point returns, and typed commands for map movement, map position, party switching, talk choice, fishing, relogin, and time setting; capture hosts can now answer upstream 1.0...6.0 `GetBigMapZoomLevel()` from the current big-map UI templates. When no template provider is injected, `BvImage` direct upstream resource paths and upstream `feature:asset` aliases such as `AutoSkip:icon_option.png` or `QuickTeleport:MapScaleButton.png` are resolved through `BGIAssetResolver` and matched with the Swift template engine; the Rust bridge still runs through the main-actor `AppState` observation path. The remaining work is OpenCV-backed image objects, full async/cancellation semantics, full immediate `genshin.*` command execution, and completing Pathing navigation details such as `TpTask.GetBigMapRect`, SIFT/feature big-map localization, country/area switching, nearest teleport lookup, and rich action handlers.

Scheduler JSON compatibility follows upstream `ScriptGroupProject`: BetterGI-mac decodes `projects[].jsScriptSettingsObject` into the executor settings JSON and writes the object key back out, so Windows scheduler files such as `User/ScriptGroup/狗粮+锄地.json` keep their per-JS settings intact.

`BGIScriptRepositoryWebBridge` is the Swift service-layer equivalent of upstream `RepoWebBridge`. It returns `repo_updated.json` when present, falls back to `repo.json`, exposes current subscribed paths as JSON, imports `bettergi://script?import=` links through the subscription store, clears or resets `hasUpdate` flags, and serves repository text/image files with extension allow-lists and path traversal checks. The actual WKWebView container can bind to this service later without duplicating repository file or subscription logic.

YOLO is currently scaffolded through upstream model registrations plus `YOLODetectionPostProcessor` for letterbox coordinate restoration, confidence filtering, same-class NMS, and BGI-style grouping by label. Real ONNX session execution and model-specific labels are still pending.

### HUD

The HUD is an AppKit `NSPanel` configured as:

- borderless
- transparent
- non-activating
- mouse passthrough
- all Spaces/full-screen auxiliary
- screen-saver level for future game overlay use

The HUD content is SwiftUI and reads the same `AppState` as the main window.

The current HUD is a transparent 16:9 mock game overlay rather than a compact notification card. It includes:

- FGI-font realtime status list for pickup, dialog, hangout, fishing, and teleport.
- Monospaced log box bound to `recentLogs`.
- Three-column metrics grid following BetterGI `OverlayMetricItem` order.
- UID cover, direction markers, recognition boxes, and mock map points/path.
- Centered edit-mode copy matching upstream `MaskWindow.xaml` behavior.

The map points and recognition boxes are static placeholders until capture and map-mask data are available.

### Future Rust Core

The planned Rust core should own:

- Template matching through the `TemplateMatcher` trait; current `PixelTemplateMatcher` consumes BGRA frames and PNG templates and is exposed to Swift through `macgi_core_match_template`, with OpenCV acceleration still pending.
- Recognition loops.
- Task scheduling decisions.
- Frame analysis metrics.

Swift should continue to own:

- macOS windows and overlay.
- Capture permissions and capture delivery.
- Input permissions and action dispatch.
- User configuration and logs presentation.

The draft C FFI contract is in `shared/macgi_core.h`.

## Integration Path

1. Keep the betterGI-mac Swift UI and Mock services compiling.
2. Implement a Rust dynamic library matching `shared/macgi_core.h`.
3. Add a Swift `RustCoreBridge` that conforms to `CoreBridge`.
4. Keep `MockCoreBridge` as fallback and test fixture.
5. Route frame delivery from capture providers to Rust recognition backends when the dylib is available, with Swift template matching as fallback.
6. Surface core events back into `AppState`.
