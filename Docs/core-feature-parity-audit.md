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
