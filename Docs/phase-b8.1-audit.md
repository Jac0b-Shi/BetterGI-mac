# B8.1 Audit: Input Send Extraction

**Status:** Audit only — no code changes
**Predecessor:** B7 complete (commit `0cf37a7`)

---

## 1. Input Call Sites in AutoPickTrigger.OnCapture()

Five call sites in `BetterGenshinImpact/GameTask/AutoPick/AutoPickTrigger.cs`:

| # | Line | Code | IInputBackend equivalent | Trigger condition |
|---|------|------|--------------------------|-------------------|
| 1 | 198 | `Simulation.SendInput.Mouse.VerticalScroll(2)` | `Scroll(2)` | Scroll-wheel icon detected |
| 2 | 210 | `Simulation.SendInput.Keyboard.KeyPress(PickVk)` | `KeyPress(pickVk)` | `ForceInteraction == true` |
| 3 | 257 | `Simulation.SendInput.Keyboard.KeyPress(PickVk)` | `KeyPress(pickVk)` | No list, no chat/settings icon |
| 4 | 355 | `Simulation.SendInput.Keyboard.KeyPress(PickVk)` | `KeyPress(pickVk)` | Whitelist match |
| 5 | 386 | `Simulation.SendInput.Keyboard.KeyPress(PickVk)` | `KeyPress(pickVk)` | All checks passed |

**Only two IInputBackend operations needed by AutoPickTrigger:** `KeyPress(BgiKey)` × 4 + `Scroll(int)` × 1.

---

## 2. Scroll Semantics Audit

**Interface (`IInputBackend.cs:40`):** `void Scroll(int delta)` — no inline doc on unit.

**Call site:** `Simulation.SendInput.Mouse.VerticalScroll(2)` — Win32 equivalent: `mouse_event(MOUSEEVENTF_WHEEL, ...)` with `dwData = 2 * WHEEL_DELTA = 2 * 120 = 240`.

**Contract recommendation:** `Scroll(n)` means `n` logical scroll "clicks" — equivalent to `MOUSEEVENTF_WHEEL` with `WHEEL_DELTA * n` on Windows. Positive = same direction as Windows `VerticalScroll(+n)`. Do NOT describe in terms of "scroll content up/down" — macOS natural-scrolling setting reverses the visual direction but the input unit must be consistent.

**Current gap:** No macOS `IInputBackend` implementation exists in C# Core. The Swift/CGEvent bridge (future work) must honor this contract. The `RecordingInputBackend` in tests only records calls; real macOS input is deferred to the Swift-host integration phase.

---

## 3. Full IInputBackend Interface — Win32 Mapping

The `Win32InputBackend` cannot implement only `KeyPress` + `Scroll`. It must implement the full `IInputBackend` interface because `DesktopRegion` already depends on mouse methods, and other triggers will follow.

| IInputBackend method | Windows implementation source | Notes |
|---------------------|------------------------------|-------|
| `KeyDown(BgiKey)` | Map `BgiKey` → `User32.VK`; `Fischless.Keyboard.KeyDown()` | Fischless wraps `SendInput(KEYBDINPUT)` |
| `KeyUp(BgiKey)` | Same mapping; `Fischless.Keyboard.KeyUp()` | |
| `KeyPress(BgiKey)` | KeyDown → Thread.Sleep → KeyUp | B8.1 call site: `Keyboard.KeyPress(PickVk)` |
| `MoveMouseTo(screenX, screenY)` | Convert screen pixels → 0–65535 absolute coordinates; `Fischless.Mouse.MoveMouseTo()` | Interface doc: "screen-pixel coordinates" — conversion is backend responsibility |
| `MoveMouseBy(deltaX, deltaY)` | `Fischless.Mouse.MoveMouseBy()` | Relative move |
| `LeftButtonDown()` | `Fischless.Mouse.LeftButtonDown()` | |
| `LeftButtonUp()` | `Fischless.Mouse.LeftButtonUp()` | |
| `LeftClick(screenX, screenY)` | MoveMouseTo + LeftButtonDown + LeftButtonUp | |
| `Scroll(delta)` | Convert `delta` clicks → `delta * WHEEL_DELTA`; `Fischless.Mouse.VerticalScroll(delta)` | B8.1 call site: `Mouse.VerticalScroll(2)` |

**Critical:** MoveMouseTo coordinate conversion. The IInputBackend contract states "screen-pixel coordinates." Win32 `SendInput` absolute mouse events use 0–65535 normalized coordinates. The conversion `(screenX * 65535) / screenWidth` must be applied inside `Win32InputBackend.MoveMouseTo()`. Do NOT push this conversion to callers.

---

## 4. AutoPickTrigger Construction Points (all projects)

### Production paths

| # | File:line | Constructor | Context |
|---|-----------|-------------|---------|
| 1 | `GameTaskManager.cs:47` | `new AutoPickTrigger()` | Windows dispatcher startup |
| 2 | `GameTaskManager.cs:97` | `new AutoPickTrigger(externalConfig)` | Windows script launch |

### macOS composition

| # | File:line | Constructor | Context |
|---|-----------|-------------|---------|
| 3 | `MacAutoPickComposition.cs:52` | `new AutoPickTrigger(config, state, provider)` | macOS composition root |

### Verification (tests)

| # | File:line | Constructor | Context |
|---|-----------|-------------|---------|
| 4-9 | `Program.cs:184-222` | Various overloads | B5 verification |

No reflection/Activator-based construction found outside tests.

---

## 5. Windows Injection Chain

### 5.1 TaskTriggerDispatcher → GameTaskManager → trigger

```
TaskTriggerDispatcher.Start(hWnd, mode)
  ├─ GameCaptureFactory.Create(mode)
  ├─ TaskContext.Instance().Init(hWnd)
  ├─ AutoPickAssets.Instance.Configure(_autoPickConfigProvider)
  ├─ GameTaskManager.LoadInitialTriggers()
  │   └─ new AutoPickTrigger()
  └─ GameCapture.Start(...)
```

### 5.2 AddTrigger path

```
TaskTriggerDispatcher.AddTrigger(name, externalConfig)
  └─ GameTaskManager.AddTrigger(name, externalConfig)
      └─ new AutoPickTrigger(externalConfig)
```

Script-layer callers of `AddTrigger("AutoPick", null)`:
- `Dispatcher.cs:93` — script engine
- `ScriptGroupProject.cs:243` — script group
- `AutoLeyLineOutcropTask.cs:347` — task-specific trigger activation

All go through `TaskTriggerDispatcher.Instance().AddTrigger()` → static `GameTaskManager.AddTrigger()`.

### 5.3 TaskRunner reload path

```csharp
// TaskRunner.cs:188-190
TaskTriggerDispatcher.Instance().ClearTriggers();
TaskTriggerDispatcher.Instance().SetTriggers(GameTaskManager.LoadInitialTriggers());
```

`TaskRunner` directly calls static `GameTaskManager.LoadInitialTriggers()` — it does NOT go through a dispatcher-owned creation method. `TaskRunner` has no access to `dispatcher._inputBackend`.

**Correct fix:** NOT exposing `dispatcher.InputBackend` publicly. Instead, add a dispatcher instance method that encapsulates the reload:

```csharp
// TaskTriggerDispatcher
public void ReloadInitialTriggers()
{
    SetTriggers(GameTaskManager.LoadInitialTriggers(_inputBackend));
}
```

```csharp
// TaskRunner.cs (after B8.1)
TaskTriggerDispatcher.Instance().ClearTriggers();
TaskTriggerDispatcher.Instance().ReloadInitialTriggers();
```

This keeps the backend private to the dispatcher, keeps TaskRunner unaware of GameTaskManager's dependencies, and centralizes composition responsibility.

### 5.4 GameTaskManager is static — no constructor injection

`GameTaskManager` is `internal class` with all static methods. Injection flows through method parameters:

```csharp
// GameTaskManager signature changes
public static List<ITaskTrigger> LoadInitialTriggers(IInputBackend inputBackend) { ... }
public static bool AddTrigger(string name, object? config, IInputBackend inputBackend) { ... }
```

All callers of these methods must pass the backend. The dispatcher holds the backend and forwards it.

### 5.5 TaskTriggerDispatcher constructor callers (full audit)

| Caller | File:line | Mechanism |
|--------|-----------|-----------|
| DI container | `App.xaml.cs:155` | `services.AddSingleton<TaskTriggerDispatcher>()` |
| TaskSettingsPageViewModel | `TaskSettingsPageViewModel.cs:227` | DI-injected parameter |
| HomePageViewModel | `HomePageViewModel.cs:79` | DI-injected parameter |
| Anywhere via Instance() | `TaskTriggerDispatcher.cs:67` | Singleton accessor (not a new) |

Only ONE instantiation point: DI in `App.xaml.cs`. All ViewModels receive it via DI. All other code accesses the singleton via `Instance()`.

After adding `IInputBackend` to the constructor, only the DI registration line changes:
```csharp
services.AddSingleton<TaskTriggerDispatcher>();        // before
services.AddSingleton<TaskTriggerDispatcher>(sp =>      // after
    new TaskTriggerDispatcher(
        sp.GetRequiredService<IAutoPickConfigProvider>(),
        sp.GetRequiredService<IInputBackend>()));
```

---

## 6. WPF Project Gaps

### 6.1 Missing Platform.Abstractions reference

The WPF csproj (`BetterGenshinImpact/BetterGenshinImpact.csproj`) has no `<ProjectReference Include="..\BetterGenshinImpact.Platform.Abstractions\..." />`. This reference must be added so `BgiKey`, `IInputBackend`, `BgiRect` are available.

### 6.2 Missing IInputBackend implementation

No class in the WPF project implements `IInputBackend`. `Win32InputBackend` must be created (see §3 mapping).

### 6.3 DesktopRegion uses nonexistent PlatformServices.Input

`DesktopRegion.cs` references `PlatformServices.Input` which is only defined in Core's `Shim/PlatformServices.cs`. This file does not exist in the WPF project and will not compile as-is.

**DesktopRegion is NOT B8.1 scope.** It should not be fixed with `#if` guards (creates platform branches violating the extraction goal). It needs a proper DI migration — but that involves both instance methods and static methods, and affects mouse interaction, not keyboard input.

**B8.1 strategy:** if WPF build is blocked by DesktopRegion, apply a minimal temporary guard (e.g., `#if BGI_PLATFORM_MAC` on PlatformServices code paths, or add a WPF PlatformServices shim). Full DesktopRegion migration is a separate follow-up item; document it as debt.

### 6.4 WPF prerequisites (B8.1.0)

1. Add `BetterGenshinImpact.Platform.Abstractions` reference to WPF csproj
2. Create `BetterGenshinImpact/Core/Runtime/Windows/Win32InputBackend.cs` implementing `IInputBackend` (full interface, see §3)
3. Register `IInputBackend` → `Win32InputBackend` in `App.xaml.cs` DI
4. Inject into `TaskTriggerDispatcher` constructor (one DI registration line change)
5. Handle DesktopRegion compile break (minimal temporary fix; full migration deferred)

### 6.5 WPF Build Status (B8.1.0c)

#### Adapter Gate (isolated + required)

| Check | Status | Notes |
|-------|--------|-------|
| `Win32InputHelpers.cs` missing `using System;` | ❌ Fixed 814d42e → next | `ArgumentOutOfRangeException`, `ArgumentException`, `Math` unresolvable |
| `Win32InputBackend.cs` missing `using System.Threading;` | ❌ Fixed 814d42e → next | `Thread.Sleep` unresolvable |
| Interface + Fischless + Vanara method signatures | ✅ No errors in either CI run | |
| DI registration (`IInputBackend → Win32InputBackend`) | ✅ No errors | |
| Isolated adapter build project | ✅ NEW: `Test/BetterGenshinImpact.Core.AdapterBuild/` | Compiles only adapter + dependencies, not full WPF app |

The adapter-specific errors are limited to two missing `using` directives.
After the fix, the isolated adapter gate (CI job `adapter-gate`) must pass 0 errors.

#### Full WPF Build (known-failing baseline, 146 errors)

The full `BetterGenshinImpact.csproj` build produced **146 errors / 312 warnings** (second CI run,
after restoring `TaskTriggerDispatcher.cs` usings). None of the adapter-specific fixes resolve these.
They are pre-existing platform-compatibility regressions from the branch extraction.

**Error classification (by root cause):**

| Category | Estimated error count | Representative files | Need |
|----------|---------------------|---------------------|------|
| A. BgiKey ↔ User32.VK boundary | ~40 | `AutoPickTrigger`, `AutoSkipTrigger`, `AutoDomainTask`, `BvSimpleOperation`, `TaskTriggerDispatcher`, `KeyMouseMacroPlayer`, multiple Job/Script files | Windows adapter must convert at boundary; callers must not pass `BgiKey` to `User32.VK` API directly |
| B. BgiRect ↔ RECT boundary | ~8 | `TaskTriggerDispatcher`, `PictureInPictureWindow`, `Job` files | Same as A — boundary conversion missing |
| C. GameCaptureRegion Windows input helpers | ~35 | `Region`, `GameCaptureRegion`, `ImageRegion`, callers of `GameRegion1080PPosClick`, `BackgroundClick`, etc. | Drawing-input extension methods removed/not linked into WPF project |
| D. DesktopRegion compatibility | ~10 | `DesktopRegion`, callers of parameterless constructor, `PlatformServices.Input` | Constructor signature changed; `PlatformServices` not defined in WPF project |
| E. Missing imports (wider) | ~15 | Scattered across WPF files | Files missing `System`, `System.Threading`, `System.Linq` etc. |
| F. AutoPickAssets/BgiKeyMapper references | ~6 | Callers expecting `BgiKeyMapper.ToUser32Vk` or `AutoPickAssets.PickVk` as `User32.VK` | Need conversion or old method restored |
| G. Other/systemic (shim removal fallout) | ~32 | Various | `GameTaskManager.TriggerDictionary`, `App.GetLogger`, shim-dependant APIs |

**Key observation:** These 146 errors are NOT introduced by B8.1. They were latent since earlier phases
(Platorm.Abstractions, BgiKey/BgiRect introduction) removed Windows-specific shims or changed shared types
without providing Windows-side conversion paths. The full WPF build has not been compiled on any platform
since the cross-platform extraction began.

**Strategy:** No attempt to fix all 146 errors in a single pass. Each B8.x phase should:
1. Pass its isolated gate (adapter, helpers, etc.)
2. Optionally resolve the WPF-compatibility categories directly relevant to its scope
3. Never depend on the full WPF build being green for forward progress
4. Reserve a dedicated restoration phase (B8.Z) for the full WPF compatibility cleanup

---

## 7. macOS Runtime Backend Status

| Layer | Implementation | Status |
|-------|---------------|--------|
| Verification | `RecordingInputBackend` | Exists — records calls, no real input |
| C# Core `IInputBackend` | None | No implementation in Core |
| Swift/CGEvent bridge | Future | The real macOS host must supply an `IInputBackend` instance before `MacAutoPickComposition.Compose()` can accept it |

**Current path:** `MacAutoPickComposition.Compose()` receives `IInputBackend`. The macOS host must create the backend and pass it. The Swift bridge (future integration) will create a `MacCGEventBackend : IInputBackend` and pass it to `.NET Core` via the bridge.

**Verification tests use `RecordingInputBackend`** — this is sufficient for B8.1 tests because they verify that the right backend methods are called, not that actual input events reach the OS.

---

## 8. Migration Strategy: Option B — Required Injection

### Master constructor

```csharp
public AutoPickTrigger(
    AutoPickExternalConfig? config,
    IAutoPickRuntimeState? runtimeState,
    IAutoPickConfigProvider? configProvider,
    IInputBackend inputBackend)
{
    ArgumentNullException.ThrowIfNull(inputBackend);
    _inputBackend = inputBackend;
    ...
}
```

- `IInputBackend` is **required** (non-nullable, no fallback)
- `IAutoPickConfigProvider` and `IAutoPickRuntimeState` remain **nullable** for B8.1
- `TaskContext`/`RunnerContext` fallbacks persist for config + runtime state until B8.2/B8.3

### Old overload disposition

| Overload | Disposition |
|----------|------------|
| `new AutoPickTrigger()` | **Delete** — no backend |
| `new AutoPickTrigger(config)` | **Delete** — no backend |
| `new AutoPickTrigger(config, state)` | **Delete** — no backend |
| `new AutoPickTrigger(config, state, provider)` | **Add IInputBackend parameter** |

---

## 9. Migration Steps (B8.1 implementation)

| Step | Description | Key files |
|------|-------------|-----------|
| B8.1.0 | WPF prerequisites: Platform.Abstractions ref + Win32InputBackend + DI + DesktopRegion fix | WPF csproj, new file, App.xaml.cs |
| B8.1.1 | IInputBackend → TaskTriggerDispatcher constructor; DI line update | TaskTriggerDispatcher.cs, App.xaml.cs |
| B8.1.2 | LoadInitialTriggers(IInputBackend) → passes to trigger constructor | GameTaskManager.cs |
| B8.1.3 | AddTrigger(name, config, IInputBackend) → passes to trigger constructor | GameTaskManager.cs |
| B8.1.4 | Dispatcher.AddTrigger() forwards _inputBackend to GameTaskManager | TaskTriggerDispatcher.cs:109-121 |
| B8.1.5 | New ReloadInitialTriggers() dispatcher method; TaskRunner calls it | TaskTriggerDispatcher.cs, TaskRunner.cs:190 |
| B8.1.6 | AutoPickTrigger: add IInputBackend param to master ctor; delete old overloads | AutoPickTrigger.cs |
| B8.1.7 | Replace 5 Simulation.SendInput calls with `_inputBackend.KeyPress(xxx)` / `_inputBackend.Scroll(xxx)` | AutoPickTrigger.cs |
| B8.1.8 | MacAutoPickComposition passes IInputBackend | MacAutoPickComposition.cs |
| B8.1.9 | Script callers: AutoLeyLineOutcropTask, ScriptGroupProject, Dispatcher | 3 files |
| B8.1.10 | Verification: all 6 AutoPickTrigger calls pass RecordingInputBackend | Program.cs |
| B8.1.11 | Build + run verification | |

**Do NOT:**
- Create wrapper interfaces (IAutoPickInput, etc.)
- Change IInputBackend API
- Keep static fallback `_inputBackend ?? PlatformServices.Input`
- Touch B8.2/B8.3/OCR/Yap
- Delete Shim files
- Make DesktopRegion a full B8.1 deliverable (temporary fix only)
