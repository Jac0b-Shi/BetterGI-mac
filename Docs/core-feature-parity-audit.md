# Core feature parity audit

This audit compares the macOS Core-backed feature surface with the current
upstream WPF task pages. A feature is complete only when the original C# task
or trigger runs and every applicable user setting is read and written by Core.
Swift may render DTOs, but does not define task defaults or persist BetterGI
configuration.

## Realtime triggers

| Trigger | Production execution | Settings parity | Remaining work |
| --- | --- | --- | --- |
| GameLoading | complete | not user-configurable upstream | None. It remains an internal initial trigger. |
| AutoPick | complete | complete | Fast mode, OCR engine, lists, list enable flags and pick key use Core-owned settings. |
| AutoSkip | complete | complete for applicable macOS controls | Dialogue skipping, fixed delay, process-audio VAD wait, option priority, custom priority text, submit, popup, daily reward, expedition and hangout settings are Core-owned, atomically persisted and hot-updated on the live trigger. Background activation and PiP remain intentionally absent because macOS pauses input when the game loses focus. |
| AutoFish | complete | complete | Upstream exposes the realtime half-auto enable switch and directs full automation to the independent task. |
| AutoEat | complete | complete | Enable state, check interval and eat interval use the upstream config. |
| QuickTeleport | complete | complete | Enable state, list click delay, panel wait delay and hotkey mode use the upstream config. |
| MapMask | complete | complete | The realtime page owns only the upstream mini-map-mask switch. Provider, language and point selection belong to the big-map HUD picker. |
| SkillCd | complete | complete | Custom role fallback rules, trigger-on-skill, hide-at-zero, position, gap, scale and four colors are Core-owned and hot-updated. The macOS HUD renders the same ready/normal color and scale semantics independently from the recognition-debug overlay switch. |

The production initial-trigger registry contains exactly these eight entries.
`trigger.list` is the only source used by Swift for availability, enabled state,
priority, exclusivity and whether an expander may be shown.

## Independent tasks

| Task | Shared C# execution | Settings/input parity |
| --- | --- | --- |
| AutoGeniusInvokation | complete | complete |
| AutoWood | complete | complete |
| AutoFight | complete | complete for the upstream task page fields used by the task |
| AutoDomain | complete | complete |
| AutoBoss | complete | complete |
| AutoStygianOnslaught | complete | complete |
| AutoFishing | complete | complete; the Windows-only Torch DLL field is read-only on macOS |
| AutoLeyLineOutcrop | complete | complete |
| AutoMusicGame | complete | complete |
| AutoAlbum | complete | shares the upstream AutoMusicGame configuration |
| AutoCook | complete | complete |
| AutoArtifactSalvage | complete | complete |
| AutoRedeemCode | complete | multiline launch input is owned by the task action, not a settings document; the descriptor therefore does not expose an expander |

The upstream Grid icon collection and model-accuracy entries are developer
tools rather than normal automation tasks and are intentionally absent from the
production macOS task catalog. One-dragon execution remains a separate workflow
surface and must not be represented as an independent task card. The shared
`OneDragonPlan` now owns old/new configuration compatibility, explicit order,
duplicate task names, enabled state and resume-marker fallback; the Windows
ViewModel consumes that same plan for display and execution-window selection.
Task construction, ScriptGroup mixing, notification sequencing and completion
actions still remain in the WPF layer, so macOS does not expose a production
OneDragon navigation entry yet. A static gate rejects reintroducing the removed
hard-coded Swift page before that Core-owned workflow exists.

## Runtime pathing actions

`PathExecutor` and `ActionFactory` now share one handler registry. The runtime
library verifier uses the production `PathingTask` serializer and asks
`PathExecutor.SupportsAction` for every non-empty waypoint action, so the gate
cannot pass by maintaining a second test-only list.

The current user runtime library contains 4,978 route documents, 79,469
waypoints and 18 action codes. All are resolved by the production executor:

```text
anemo_collect      combat_script     electro_collect
fight              fishing           force_tp
hydro_collect      linnea_mining      log_output
mining             nahida_collect    pick_around
pick_up_collect    pyro_collect      set_time
stop_flying        up_down_grab_leaf use_gadget
```

This is a local runtime-data gate because CI does not contain the user's
downloaded route library:

```bash
scripts/verify-pathing-library.sh
scripts/verify-pathing-library.sh "/path/to/runtime-root"
```

## Command-line scheduling

The macOS frontend accepts the upstream `--startGroups <group name...>` spelling.
It starts the runtime only after permissions, a real game window and Core are
ready, filters missing names against the Core-owned catalog, then sends the
remaining ordered names in one `scheduler.runGroups` RPC. Core owns the
continuous-group flag, two-second group interval, one task lifecycle and the
upstream `TaskProgress` document. Normal UI execution of one selected group
continues to use `scheduler.run`.

## Supporting workflows

### Key/mouse recording and playback

The production recording page no longer contains sample scripts or unavailable
actions. AppKit owns the macOS event tap and forwards physical keyboard, mouse,
drag and wheel events only while the selected game process is frontmost. Core
owns the `User/KeyMouseScript` catalog, upstream filename convention, ordering,
negative-time filtering, 20 ms mouse-move merging, JSON serialization and
shared `KeyMouseMacroPlayer` playback. List, save, rename, delete, play, stop
and status operations are exposed through authenticated RPC.

### Notifications

Core owns `notificationConfig.jsNotificationEnabled` and maps the upstream
native-notification switch to the macOS notification center. Script
notifications still pass through `IScriptHostServices`, then cross the platform
callback boundary to `UNUserNotificationCenter`; Swift does not decide whether
a script may emit. The production page renders the Core-owned event subscription
list, screenshot option and all 13 upstream remote channels: Webhook, WebSocket,
Feishu, OneBot, Work Weixin, email, Bark, Telegram, xxtui, DingTalk, Discord,
ServerChan and MeoW. Their configuration, validation, notifier construction,
refresh and test sends use the shared `NotificationService`; Swift only renders
field descriptors and forwards save/test RPC requests. Configuration-group
start/end, task cancellation/error, AutoAlbum, AutoDomain, AutoBoss,
AutoLeyLineOutcrop and AutoStygianOnslaught events also enter that same service,
so event subscriptions, screenshots and every enabled remote channel apply to
real unattended execution rather than only to JS and test notifications. The
static gate rejects direct runtime `notification.emit` calls outside the native
macOS notifier adapter, and the `notification-routing` Fast suite verifies
Webhook delivery plus subscription filtering through the production adapters.

### Auxiliary controls

The production page exposes the two upstream hold-continuation controls, the
Neuvillette turn-around macro, quick artifact enhancement, quick shop purchase,
quick Serenitea Pot entry/exit, one-key reward claiming, one-key combat and the
upstream confirm/cancel button hold actions.
Core reads and writes
`macroConfig`,
supplies the configured `KeyBindingsConfig` pickup and jump virtual keys, and
owns the 200/300 ms thresholds, repeat intervals, turn distance and turn
interval. The shared `TurnAroundMacro` owns the zero-distance normalization,
mouse movement and wait sequence; Windows and macOS only compose their
platform input/configuration adapters. The shared
`QuickEnhanceArtifactMacro` preserves the upstream 1920x1080 click sequence
and reads `EnhanceWaitDelay` from the same Core-owned config on both
platforms. The shared `DialogButtonClickMacro`
preserves the upstream black, white and co-op button recognition order; macOS
reads the current shared-memory frame and routes the recognized click through
the cancellable foreground input gate. The shared `QuickBuyTask` owns the
Serenitea Pot template branch, ordinary-shop branch and both drag/click
sequences; macOS supplies only shared-memory capture, focus-safe mouse input
and overlay cleanup. The shared `OneKeyClaimRewardTask` owns the upstream
click-once/hold state machine, top-left candidate ordering, blank-continue ESC
handling, 30-click cap, scroll chunking and release cancellation. Core persists
the original mode, scroll-enable and scroll-amount fields; macOS supplies only
capture, coordinate conversion, focus-safe input and logging.
The shared `QuickSereniteaPotTask` retains the upstream bag/pot template
retries, white-confirm recognition, main/big-map recovery and OCR-gated
enter/leave interaction. Core owns its one-shot deduplication and runtime-stop
cancellation; macOS supplies only capture, foreground-safe input, timing,
logging and overlay cleanup.
The shared `OneKeyFightTask` owns the upstream three-mode press/release state
machine, current-avatar recognition, per-avatar macro selection, command loop
and residual key release. Core persists the original enable, mode and priority
fields and owns the user macro-file location; Windows and macOS only compose
their settings, logging and filesystem adapters.

AppKit observes physical key state only while the game is frontmost. Hold
hotkeys forward both press and release edges, and release remains deliverable
after focus loss so Core can cancel an input blocked at the foreground safety
gate. All generated input carries an injection marker so recording and
monitoring cannot feed back on BetterGI-generated events. Other upstream macro
actions remain absent from the page rather than appearing as clickable
placeholders.

### Hotkeys

Core owns the supported hotkey catalog and persists the original upstream
`hotKeyConfig` property names and `KeyboardMonitor` / `GlobalRegister` values.
The macOS page no longer renders sample bindings. It records physical keyboard
or side-button input in the upstream WPF string format, clears duplicate
bindings atomically, and reloads the same Core-owned document.

AppKit observes the configured physical keys. `KeyboardMonitor` bindings are
accepted only while the runtime is active and the selected Wine game process
is frontmost; `GlobalRegister` bindings remain available for system control.
Generated BetterGI input is marked and excluded from hotkey observation. Core
executes cancellation, shared `RunnerContext` suspension, trigger toggles and
solo-task toggles, turn-around and dialog-button hold actions. Swift owns only
runtime capture start/stop, overlay presentation and macOS key/mouse recording.
The QuickTeleport hold binding is not dispatched as an action: Core reads its
live-updated key through the existing physical key-state callback, matching the
upstream trigger contract.

Only upstream entries whose action has a complete production path are exposed.
The game-screenshot hotkey executes the shared `GameScreenshotTask` on both
Windows and macOS. Core owns timestamped PNG naming, the upstream UID cover and
the `log/screenshot` output contract; macOS reads the real shared-memory frame.
The path-recorder and add-waypoint hotkeys execute the shared
`PathRecorderTask`. Core owns map/matching settings, stable position lookup,
teleport/path waypoint semantics, route metadata, timestamped JSON naming and
the recording lifecycle. Windows retains the optional WebView editor adapter;
macOS follows the upstream no-editor branch and saves directly to
`User/AutoPathing`. The upstream developer big-map-position hotkey executes the
shared `TpTask.GetPositionFromBigMap` path, including the existing map UI check,
SIFT matching, shared-memory capture and Core logging; Swift only observes and
forwards the configured physical key.

### Game key bindings

Core owns the complete upstream `keyBindingsConfig` action/menu catalog,
default Windows virtual-key values, macOS-supported key options, validation and
atomic persistence. The macOS page consumes `keyBinding.settings.get/save`
descriptors and does not maintain an editable Swift business catalog. Saving a
binding invalidates the shared `GameActionKeyResolver` immediately and refreshes
the hold-to-repeat pickup/jump snapshot, so built-in tasks and auxiliary
controls use the new key without restarting Core.

The upstream `globalKeyMappingEnabled` boundary is preserved. Shared built-in
tasks always execute their configured `GIActions`; JavaScript globals and
combat-script string keys retain their literal defaults while the switch is
off, and map only the exact upstream default-key set while it is on. Mouse
attack/sprint, elemental sight and Paimon-menu keys remain excluded from global
mapping as upstream requires. Unsupported legacy key values are shown
truthfully and cannot be re-saved as if the macOS input bridge supported them.
The `key-bindings` Fast suite covers persistence, hot update, validation and
external-key mapping, while `runtime-settings` verifies the authenticated Unix
socket RPC round trip.

## Verification tiers

Use the smallest tier that owns the changed behavior:

```bash
# Settings, catalogs, scheduler editing and other contract changes.
scripts/verify-core-development.sh fast

# Shared Core contracts without artifact installation or model startup.
scripts/verify-core-development.sh contracts

# Manifest, source-lock, downloader and synthetic archive checks.
scripts/verify-core-development.sh artifacts

# Locked release installation, ONNX sessions and real OCR.
scripts/verify-core-development.sh models

# Any PathExecutor, action-handler or downloaded route-library change.
scripts/verify-core-development.sh pathing

# Static architecture and production-fallback gate.
scripts/verify-core-development.sh static

# Full Core behavior, recognition, artifact and model runtime verification.
scripts/verify-core-development.sh full
```

The legacy Core and Host verifier programs remain full integration gates. New
pure contract checks belong in `BetterGenshinImpact.Core.Host.Fast.Verification`
and route-library closure checks belong in the Core-only
`BetterGenshinImpact.Pathing.Verification` project. Editing either verifier no
longer recompiles a 4,000-line integration program. The full tier builds the
dependency graph once and runs each verifier with `--no-build`; local iteration
must not use an implicit `dotnet run` build.

Measured on Apple Silicon with a warm package cache, rebuilding the legacy Core
verifier took about 16 seconds while the former unfiltered `dotnet run
--no-build` took 105 seconds. The cumulative `contracts` boundary completes 88
shared-Core checks in about 7.5 seconds including up-to-date builds. The runtime
pathing verifier completed its isolated warm loop in under 9 seconds. The
expensive full gate is therefore reserved for model, recognition, artifact,
native-runtime and phase-completion changes.

The `runtime-settings` Fast suite additionally starts the real Unix-domain RPC
server and verifies macro settings, notification settings and key/mouse
recording CRUD plus the initial `scheduler.status` snapshot through framed
authenticated requests. The isolated `scheduler-status` suite covers running,
paused, stopping and terminal transitions, stale task rejection and error
retention. This prevents direct catalog tests from masking RPC method or
payload drift without expanding the legacy integration verifier.
