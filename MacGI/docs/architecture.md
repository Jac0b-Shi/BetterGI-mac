# BetterGI-mac architecture

## Current authority

The production architecture is a SwiftUI/AppKit shell around the extracted
BetterGI C# Core Host. `Docs/core-extraction-map.md` is the source of truth for
completion and ownership.

The macOS application does not own BetterGI recognition, script, scheduler,
pathing, trigger or independent-task business logic. Historical Swift
JavaScriptCore, Rust task logic, mock scheduler and record-then-replay designs
are not production fallbacks and must not be reintroduced.

## Swift shell

Swift owns macOS integration:

- App, menu bar and Dock lifecycle.
- Game-window enumeration and stable `CGWindowID` selection.
- ScreenCaptureKit frame delivery and capture-ring publication.
- Foreground-verified `CGEvent` dispatch.
- TCC permission presentation.
- HUD/AppKit panels and presentation-only overlay rendering.
- Core process supervision, framed JSON RPC and callback acknowledgements.
- Bounded runtime log persistence.

Relevant entry points:

- `Sources/MacGI/App/AppState.swift`
- `Sources/MacGI/Runtime/BetterGICoreProcessSupervisor.swift`
- `Sources/MacGI/Runtime/BetterGICorePlatformAdapter.swift`
- `Sources/MacGI/Runtime/ScreenCaptureKitFrameProvider.swift`
- `Sources/MacGI/Runtime/CGEventInputDispatcher.swift`
- `Sources/MacGI/App/HUDPanelController.swift`

Swift may validate platform state before acknowledging a callback. It must not
interpret BetterGI manifests, mutate ScriptGroup JSON, decide recognition
results, sequence scheduler groups or report a platform action as successful
without applying it.

## C# Core Host

The self-contained `osx-arm64` Core Host owns:

- Canonical BetterGI runtime layout and configuration.
- Script repository/catalog, manifests, settings and package loading.
- ClearScript V8 and upstream host objects.
- ScriptGroup mutation, scheduling, `TaskProgress` and cancellation.
- Realtime triggers and their settings.
- Independent tasks and their settings.
- Pathing, KeyMouse and Shell execution.
- RecognitionObject, OpenCV, Paddle OCR and ONNX execution.
- Runtime artifact provisioning and recognition-resource validation.

RPC methods expose Core-owned DTOs and commands. Platform callbacks are limited
to capture, window metrics/focus, semantic input, notifications, file/folder
presentation and overlay presentation.

Captured BGRA frames cross the Swift/Core boundary through a process-scoped,
double-buffered POSIX shared-memory object. The authenticated callback carries
only committed frame metadata and the shared-memory name; production capture
never writes a frame ring under `Application Support`. The legacy
`Run/capture-ring.bin` path is accepted only by explicit verifier fixtures.

The upstream ClearScript `htmlMask` host remains C#-owned. Core preserves the
upstream window and request/response contract, while Swift implements the
platform WebView surface with `WKWebView`. Runtime stop closes every platform
HTML mask.

The upstream `--startGroups <name...>` command-line flow is parsed by Swift only
to obtain ordered names. Core receives one `scheduler.runGroups` request and
owns the continuous-group flag, two-second interval, one task lifecycle and
`TaskProgress` persistence.

## Runtime layout

The canonical runtime root is:

```text
~/Library/Application Support/betterGI-mac
```

Important children:

```text
User/                 scripts, groups and user configuration
GameTask/             generated canonical recognition assets
Assets/               provisioned models and map artifacts
Repos/                script repository checkout
Cache/Downloads/      verified source archives
Run/core.sock         authenticated Core RPC socket
log/                  bounded application and execution logs
```

`BetterGenshinImpact/GameTask` is the only source repository for recognition
assets. Packaging stages selected canonical asset directories from the manifest;
the Swift source tree must not contain a second maintained copy.

## App bundle

`MacGI/scripts/package-macgi-app.sh` builds a regular signed `APPL` bundle.
The self-contained Core publish tree is sealed under:

```text
betterGI-mac.app/Contents/Resources/BetterGICore
```

Local TCC validation requires a stable Apple Development identity. Ad-hoc
signing is restricted to explicit CI packaging smoke runs.

## Verification

Use the tiered scripts:

```bash
scripts/verify-core-development.sh fast
scripts/verify-core-development.sh contracts
scripts/verify-core-development.sh pathing
scripts/verify-core-development.sh static
scripts/verify-core-development.sh full
```

The first extraction remains incomplete until the four game-dependent projects
listed in `Docs/core-extraction-map.md` complete against a real Wine game window.
