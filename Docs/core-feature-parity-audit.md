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
surface and must not be represented as an independent task card.

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
a script may emit. The production page exposes only JS permission, native
notification permission and a real test action. Webhook, Feishu, OneBot and
other upstream notifier channels remain unexposed until their shared Core
notifier implementations are extracted.

### Auxiliary controls

The production page exposes the two upstream hold-continuation controls and
the Neuvillette turn-around macro. Core reads and writes `macroConfig`,
supplies the configured `KeyBindingsConfig` pickup and jump virtual keys, and
owns the 200/300 ms thresholds, repeat intervals, turn distance and turn
interval. The shared `TurnAroundMacro` owns the zero-distance normalization,
mouse movement and wait sequence; Windows and macOS only compose their
platform input/configuration adapters.

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
solo-task toggles. Swift owns only runtime capture start/stop, overlay
presentation and macOS key/mouse recording. The QuickTeleport hold binding is
not dispatched as an action: Core reads its live-updated key through the
existing physical key-state callback, matching the upstream trigger contract.

Only upstream entries whose action has a complete production path are exposed.
Screenshot, one-key combat/reward, quick enhancement, quick-buy, Serenitea Pot
and path-recorder hotkeys remain absent until those shared actions are
extracted.

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
recording CRUD through framed authenticated requests. This prevents direct
catalog tests from masking RPC method or payload drift.
