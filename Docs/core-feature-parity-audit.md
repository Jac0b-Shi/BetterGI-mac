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
| AutoRedeemCode | complete | multiline launch input is owned by the task action, not a settings document |

The upstream Grid icon collection and model-accuracy entries are developer
tools rather than normal automation tasks and are intentionally absent from the
production macOS task catalog. One-dragon execution remains a separate workflow
surface and must not be represented as an independent task card.

## Verification tiers

Use the smallest tier that owns the changed behavior:

```bash
# Settings, catalogs, scheduler editing and other contract changes.
scripts/verify-core-fast.sh all

# Static architecture and production-fallback gate.
scripts/verify-core-static.sh

# Full Core behavior, recognition, artifact and model runtime verification.
scripts/verify-core-full.sh
```

The legacy Core and Host verifier programs remain full integration gates. New
pure contract checks belong in `BetterGenshinImpact.Core.Host.Fast.Verification`
so editing a verifier does not recompile either 4,000-line integration program.
The full tier builds the dependency graph once and runs each verifier with
`--no-build`; local iteration must not use an implicit `dotnet run` build.
