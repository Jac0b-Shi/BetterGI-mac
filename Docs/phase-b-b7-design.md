# B7 Design: macOS Composition Root

**Phase:** B7 (macOS trigger composition root)  
**Predecessor:** B6 series (constructor split + Configure lifecycle)  
**Status:** Design review — DO NOT implement until approved

---

## 1. TaskContext/Win32 Dependency Audit in AutoPickTrigger

Before designing the composition root, we must verify that the trigger-creation call chain
does not silently re-enter `TaskContext.Instance()` or `RunnerContext.Instance` through
any of the objects the composition root creates.

### 1.1 Init() Dependencies (lines 84–107)

| Line | Code | Dependency | Resolved via |
|------|------|-----------|-------------|
| 88 | `TaskContext.Instance().Config.AutoPickConfig` | `config.Enabled` | IAutoPickConfigProvider |
| 88 | (same) | `config.BlackListEnabled` | IAutoPickConfigProvider |
| 88 | (same) | `config.WhiteListEnabled` | IAutoPickConfigProvider |
| 93 | `ReadJson(@"Assets\Config\Pick\default_pick_black_lists.json")` | `Global.ReadAllTextIfExist` + `ConfigService.JsonOptions` | Shim — Phase C |
| 94 | `ReadText(@"User\pick_black_lists.txt")` | `Global.ReadAllTextIfExist` | Shim — Phase C |
| 100 | `ReadTextList(@"User\pick_fuzzy_black_lists.txt")` | `Global.ReadAllTextIfExist` | Shim — Phase C |
| 105 | `ReadText(@"User\pick_white_lists.txt")` | `Global.ReadAllTextIfExist` | Shim — Phase C |
| 122 | `ThemedMessageBox.Error(...)` | UI (WPF) — shim in Core | Shim — Phase C |

**Conclusion for Init():** Exactly **one** `TaskContext.Instance()` call (line 88), reading `AutoPickConfig`.  
All three fields (`Enabled`, `BlackListEnabled`, `WhiteListEnabled`) are already available via `IAutoPickConfigProvider.AutoPickConfig`.

### 1.2 StopCount Property (lines 61–62)

```csharp
private int StopCount =>
    _runtimeState?.StopCount ?? RunnerContext.Instance.AutoPickTriggerStopCount;
```

This falls back to `RunnerContext` when `_runtimeState` is null (Windows parameterless path).  
When the macOS composition root passes a non-null `IAutoPickRuntimeState`, `RunnerContext.Instance` is **never** accessed.

**No change needed** — the guard already works. Verification must assert the macOS path reaches `_runtimeState.StopCount`, not the RunnerContext fallback.

### 1.3 OnCapture() Dependencies (lines 181–389)

| Line | Code | Dependency | B7 scope |
|------|------|-----------|----------|
| 198 | `Simulation.SendInput.Mouse.VerticalScroll(2)` | Win32 SendInput | Out of scope — needs platform input abstraction for scroll |
| 210, 257, 355, 386 | `Simulation.SendInput.Keyboard.KeyPress(AutoPickAssets.Instance.PickVk)` | Win32 SendInput | Out of scope — same as above |
| 214 | `TaskContext.Instance().SystemInfo.AssetScale` | Win32 window metrics | Out of scope — needs ISystemInfoProvider |
| 215 | `TaskContext.Instance().Config.AutoPickConfig` | Config offsets, OCR engine, list enabled flags | Out of scope (B8+) |
| 297 | `TextInferenceFactory.Pick.Value.Inference(...)` | Static Yap engine factory | Out of scope — ONNX static gateway |
| 310, 331 | `OcrFactory.Paddle.Ocr*(...)` | Static OCR gateway | Out of scope — already injected but statically accessed |

**OnCapture() is out of B7 scope.** The composition root creates a trigger but does not
invoke the capture loop. The Swift host is responsible for calling `OnCapture()` only after
it has set up `PlatformServices.Input`, `DesktopRegion` dimensions, and (eventually) a non-shim
`TaskContext.Instance().SystemInfo`.

### 1.4 Required Narrow Change for Init()

Make `IAutoPickConfigProvider` injectable into `AutoPickTrigger` so Init() can read
`AutoPickConfig` fields from the provider instead of `TaskContext.Instance()`:

**New field + master constructor (AutoPickTrigger.cs):**
```csharp
private readonly IAutoPickConfigProvider? _configProvider;

// Master constructor — no default value on configProvider.
// Callers must explicitly pass null if they intend the TaskContext fallback.
public AutoPickTrigger(
    AutoPickExternalConfig? config,
    IAutoPickRuntimeState? runtimeState,
    IAutoPickConfigProvider? configProvider)
{
    _autoPickAssets = AutoPickAssets.Instance;
    _externalConfig = config;
    _runtimeState = runtimeState;
    _configProvider = configProvider;
}
```

**Existing two-param overload delegates null explicitly:**
```csharp
public AutoPickTrigger(
    AutoPickExternalConfig? config,
    IAutoPickRuntimeState? runtimeState)
    : this(config, runtimeState, null)
{
}
```

This avoids silent TaskContext fallback — callers see the three-parameter signature and must
decide whether to supply a provider or explicitly pass null.

**Updated Init() (line 88 only):**
```csharp
var config = _configProvider?.AutoPickConfig
             ?? TaskContext.Instance().Config.AutoPickConfig;
```

- Windows callers (parameterless ctor / two-param ctor): `_configProvider` is null → falls back to `TaskContext.Instance().Config.AutoPickConfig` — **zero breakage**.
- macOS composition root: passes `IAutoPickConfigProvider` → `TaskContext.Instance()` is **never accessed** during Init() config lookup.
- `OnCapture()` line 215 (`TaskContext.Instance().Config.AutoPickConfig`) is NOT changed — this is a separate follow-up (B8+).

---

## 2. Composition Root Design

### 2.1 Location and Naming

**File:** `BetterGenshinImpact.Core/Composition/MacAutoPickComposition.cs`

**Not** in `Core/Adapters/`. Adapters contain interface implementations (MacCoreRuntimeAdapter, MacAutoPickRuntimeState). The composition root **creates and wires** those adapters — it is the assembler, not the assembled.

**Class name:** `MacAutoPickComposition` (not `MacTriggerFactory`). "Factory" implies a generic creation pattern; "Composition" accurately describes the responsibility: assembling the full object graph for one trigger type.

### 2.2 State Machine

A single `bool _composed` is insufficient: if `AutoPickAssets.Configure()` succeeds but
`trigger.Init()` fails, the assets singleton is already configured and cannot be re-used,
yet `_composed` is still `false` — a subsequent `Compose()` call would pass the guard then
crash on duplicate `Configure()`.

Explicit four-state machine:


| State | Meaning | Next `Compose()` behavior |
|-------|---------|--------------------------|
| `NotComposed` | Initial state — no composition has been attempted | Proceed to `Composing` |
| `Composing` | Composition is in progress (guard against re-entrant calls) | Throw: "MacAutoPickComposition is already being composed." |
| `Composed` | Composition succeeded | Throw: "MacAutoPickComposition has already been composed. Restart the application." |
| `Failed` | A previous Compose() attempt failed after partial side effects | Throw: "Previous macOS AutoPick composition failed. Restart the process." |

### 2.3 Interface

```csharp
namespace BetterGenshinImpact.Core.Composition;

public sealed class MacAutoPickComposition
{
    private enum CompositionState { NotComposed, Composing, Composed, Failed }
    private static CompositionState _state = CompositionState.NotComposed;

    public AutoPickTrigger Trigger { get; }

    private MacAutoPickComposition(AutoPickTrigger trigger)
    {
        Trigger = trigger;
    }

    /// <summary>
    /// Compose a fully-wired AutoPickTrigger for macOS.
    /// Call exactly once per process lifetime.
    /// </summary>
    /// <param name="configProvider">AutoPick configuration provider.</param>
    /// <param name="runtimeState">AutoPick runtime state (StopCount coordination).</param>
    /// <param name="externalConfig">Optional script-layer override config.</param>
    public static MacAutoPickComposition Compose(
        IAutoPickConfigProvider configProvider,
        IAutoPickRuntimeState runtimeState,
        AutoPickExternalConfig? externalConfig = null)
    {
        switch (_state)
        {
            case CompositionState.Composing:
                throw new InvalidOperationException(
                    "MacAutoPickComposition is already being composed.");
            case CompositionState.Composed:
                throw new InvalidOperationException(
                    "MacAutoPickComposition has already been composed. " +
                    "Restart the application.");
            case CompositionState.Failed:
                throw new InvalidOperationException(
                    "Previous macOS AutoPick composition failed. " +
                    "Restart the process.");
        }

        _state = CompositionState.Composing;
        try
        {
            AutoPickAssets.Instance.Configure(configProvider);
            var trigger = new AutoPickTrigger(externalConfig, runtimeState, configProvider);
            trigger.Init();

            _state = CompositionState.Composed;
            return new MacAutoPickComposition(trigger);
        }
        catch
        {
            _state = CompositionState.Failed;
            throw;
        }
    }

    /// <summary>
    /// For verification tests only. Resets composition state so tests
    /// can run Compose() multiple times in a single process.
    /// </summary>
    internal static void ResetForVerification()
    {
        _state = CompositionState.NotComposed;
        AutoPickAssets.DestroyInstance();
    }
}
```

**No `IDisposable`.** The composition currently owns no resources — no event subscriptions, no capture loop, no native handles. An empty `Dispose()` would mislead callers into thinking disposal enables re-composition. When real disposable resources appear (dispatcher hooks, capture loop registration), `IDisposable` can be added then with real semantics.

### 2.4 Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| State machine vs bool | Four-state enum (`NotComposed`, `Composing`, `Composed`, `Failed`) | `Configure` success + `Init` failure leaves assets configured; bool `_composed` does not capture this. `Failed` state requires process restart. |
| Compose error handling | try/catch with state transitions | `Composing` set before work; `Composed` on success; `Failed` on any exception. No auto-rollback (Init() may have partial file/UI side effects). |
| Parameters vs options record | Narrow constructor parameters (`IAutoPickConfigProvider`, `IAutoPickRuntimeState`, `AutoPickExternalConfig?`) | No `MacRuntimeOptions` monolith. The composition root receives already-constructed dependencies; the macOS host creates adapters. |
| `StopCount` as parameter | **Not** a parameter — comes from `IAutoPickRuntimeState.StopCount` | The int snapshot in the old `MacRuntimeOptions` design was premature. The interface reference is dynamic; future mutable implementations propagate changes automatically. |
| One compose per process | State-machine guard with specific error messages per state | Prevents double-configuration of `AutoPickAssets` singleton. `Failed` state message explicitly says "restart the process" — no false hope of retry. |
| Multiple triggers | One trigger per composition | `AutoPickAssets` is a singleton with single Configure() — creating multiple triggers sharing the same assets is valid but not currently useful. The composition exposes exactly one trigger for the current dispatcher lifecycle. |
| `ResetComposition()` public API | **Deleted.** Replaced with `internal ResetForVerification()`. | Public reset enables the dangerous dual-instance state described in B6 testing. At the process level, restart is the only safe reset path. |
| `IDisposable` | **Not implemented.** | No owned resources. Would mislead callers into thinking `Dispose()` enables re-composition. Can be added later when real resources exist. |

### 2.5 Why Not a Generic Factory

- `AutoPickAssets` is a singleton with single-call `Configure()` — the composition is intrinsically one-shot.
- The trigger-creation logic is simple (`new AutoPickTrigger(...)` + `Init()`) — a separate factory class adds indirection without abstraction.
- Adding other trigger types (AutoSkip, AutoFight) would each need their own composition root or a combined one; a generic factory pattern would constrain the initialization order unnecessarily.

---

## 3. Full macOS Creation Path (post-B7)

```
Swift host / .NET bridge
  │
  ├─ PlatformServices.Input = MacCGEventBackend            (B3-style)
  ├─ DesktopRegion.DisplayWidth/Height = screen metrics     (B3-style)
  ├─ TaskContext.Instance().SystemInfo = MacSystemInfo()    (shim)
  │
  ├─ var adapter = new MacCoreRuntimeAdapter(
  │       config, PaddleOcrModelConfig.V5, "zh-Hans")
  ├─ var state = new MacAutoPickRuntimeState(0)
  │
  └─ var composition = MacAutoPickComposition.Compose(
         adapter, state, externalConfig: null)
       ├─ AutoPickAssets.Instance.Configure(adapter)        ← uses provider's AutoPickConfig
       ├─ new AutoPickTrigger(null, state, adapter)         ← configProvider injected
       └─ trigger.Init()                                    ← reads adapter.AutoPickConfig (NOT TaskContext)
```

**Construction + Init config lookup:** TaskContext-free when `configProvider` is non-null.

**Pre-conditions still use shim:** `TaskContext.Instance().SystemInfo` must be set (shim) before the capture loop can call `OnCapture()`. This shim is B3-era — not B7 scope.

**OnCapture() still accesses TaskContext:** `AssetScale` and `AutoPickConfig` offset fields are read from `TaskContext.Instance()` at runtime (lines 214–215). Out of B7 scope — B8+.

---

## 4. Lifecycle

| Step | Actor | When | Constraint |
|------|-------|------|------------|
| Pre-condition | macOS host | Before `Compose()` | `PlatformServices.Input` set, `DesktopRegion` dimensions set, `TaskContext.Instance().SystemInfo` set (shim) |
| Compose | `MacAutoPickComposition.Compose(...)` | Once per process | Guard: `NotComposed` only; `Composing`/`Composed`/`Failed` each have distinct error messages |
| Configure | `AutoPickAssets.Configure(provider)` | Inside `Compose()` try-block | Success continues; failure → `Failed` state (no retry) |
| Init | `trigger.Init()` | Inside `Compose()` try-block | Success → `Composed` state; failure → `Failed` state |
| Trigger ready | `composition.Trigger` | After `Compose()` returns | Dispatcher can begin tick loop |
| Reset | `MacAutoPickComposition.ResetForVerification()` | **Tests only** | `internal` — resets to `NotComposed` + `DestroyInstance()` |

---

## 5. Verification Plan

### 5.1 Test Access to Internal Reset

Verification project accesses `ResetForVerification()` via reflection:
```csharp
var resetMethod = typeof(MacAutoPickComposition)
    .GetMethod("ResetForVerification", BindingFlags.NonPublic | BindingFlags.Static);
resetMethod!.Invoke(null, null);
```

This avoids adding `InternalsVisibleTo` to the production assembly for a single test-only method.

### 5.2 New Tests (added to `Program.cs`)

| # | Test | Assertion |
|---|------|-----------|
| B7.1 | Compose succeeds (provider + state, no external config) | `composition.Trigger` is non-null |
| B7.2 | Compose preserves external config reference | `_externalConfig` field == original object (reflection) |
| B7.3 | Compose preserves runtime state reference | `_runtimeState` field == original object (reflection) |
| B7.4 | Init() reads IsEnabled from provider (not TaskContext fallback) | Set `provider.AutoPickConfig.Enabled = false`; `trigger.IsEnabled` == false |
| B7.5 | Init() uses unique config value to prove provider is the source | Set `Enabled = true` on one provider; Compose → verify `trigger.IsEnabled == true`; ResetForVerification; change to `false` on another provider; Compose → verify `trigger.IsEnabled == false` |
| B7.6 | `_configProvider` field preserved on trigger | Reflection: `_configProvider` == provider reference |
| B7.7 | Double Compose throws (`Composed` state) | `InvalidOperationException` containing "already been composed" |
| B7.8 | Compose failure leads to `Failed` state, subsequent Compose throws with restart message | Simulate failure (e.g., null config triggers exception inside Init); retry Compose → `InvalidOperationException` containing "Restart the process" |
| B7.9 | After ResetForVerification, Compose succeeds again | Reconfigured trigger works; no exception |
| B7.10 | Compose with `BlackListEnabled = false` | Reflection on `_blackList` field is empty |
| B7.11 | Compose with `WhiteListEnabled = false` | Reflection on `_whiteList` field is empty |

### 5.3 Tests NOT Included (deferred or requiring controlled fixtures)

| Test | Why deferred |
|------|-------------|
| Blacklist file loading with `BlackListEnabled = true` | Requires controlled test fixtures (real Assets dir content varies by developer machine). Verification project should either copy a small fixture JSON, or defer to an integration test that runs from a known working directory. |
| `rg`-based TaskContext absence check | Not sufficient — `rg` on the composition source file doesn't prove runtime behavior. B7.4–B7.6 cover this via behavioral verification (unique config values + field reflection). |

### 5.4 Existing Tests That Must Continue to Pass

- All 57 assertions from B1–B6 (`AutoPickAssets.Configure` lifecycle, `OcrFactory` injection, `AutoPickTrigger` constructor chain, `StopCount`, property guards)
- After `ResetForVerification()` + re-Compose in B7 tests, final cleanup must restore `AutoPickAssets` singleton to configured state so no downstream assertion fails

---

## 6. Implementation Plan

| Step | Files | Description |
|------|-------|-------------|
| 7.1 | `AutoPickTrigger.cs` | Add `_configProvider` field + new three-param master ctor (no default on provider). Existing two-param ctor explicitly delegates null. Update `Init()` line 88 to prefer provider over `TaskContext`. |
| 7.2 | `Core/Composition/MacAutoPickComposition.cs` | New file. Four-state enum, `Compose()` with try/catch, `ResetForVerification()`. No `IDisposable`. |
| 7.3 | `BetterGenshinImpact.Core.csproj` | Add `<Compile Include="Composition/MacAutoPickComposition.cs" />` |
| 7.4 | `Test/.../Program.cs` | Add B7.1–B7.11 test assertions. Reflection access to `ResetForVerification`. Final cleanup restores singleton state. |
| 7.5 | Build + verify | `dotnet build` zero errors; `dotnet run` all tests pass |

### 7.1 Detail: AutoPickTrigger.cs Changes

**New field:**
```csharp
private readonly IAutoPickConfigProvider? _configProvider;
```

**New master constructor (replaces current three-param at line 76):**
```csharp
public AutoPickTrigger(
    AutoPickExternalConfig? config,
    IAutoPickRuntimeState? runtimeState,
    IAutoPickConfigProvider? configProvider)
{
    _autoPickAssets = AutoPickAssets.Instance;
    _externalConfig = config;
    _runtimeState = runtimeState;
    _configProvider = configProvider;
}
```

**Updated existing two-param overload (delegates null explicitly):**
```csharp
public AutoPickTrigger(
    AutoPickExternalConfig? config,
    IAutoPickRuntimeState? runtimeState)
    : this(config, runtimeState, null)
{
}
```

Parameterless and config-only overloads chain through the two-param overload unchanged.

**Init() change (replace line 88):**
```csharp
var config = _configProvider?.AutoPickConfig
             ?? TaskContext.Instance().Config.AutoPickConfig;
```

---

## 7. Out of Scope (Phase C / B8+)

| Item | Status | Resolution |
|------|--------|------------|
| OnCapture() TaskContext reads | Present (line 214–215) | Needs ISystemInfoProvider + broader config migration (B8) |
| Simulation.SendInput | Win32 | IInputBackend already exists; OnCapture needs migration (B8) |
| OcrFactory static gateway | Static singleton | Needs DI container or composition-scoped factory (C) |
| TextInferenceFactory static gateway | Static singleton | Same as OcrFactory (C) |
| Shim deletion | 17 files remain | Gated on zero direct callers (C) |
| Global file I/O abstraction | Shim in Core | Needs IFileSystem / IAssetPath (C) |
| ThemedMessageBox | Shim in Core | Needs IUserInteractionService (C) |
| Multiple trigger types | Only AutoPick | MacAutoPickComposition is single-purpose; future MacComposition could compose all types |
