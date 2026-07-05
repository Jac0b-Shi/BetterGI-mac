# Porting Audit: TaskContext & RunnerContext

**Branch:** `mac-core-extraction` (commit `374a023`)
**Date:** 2026-07-05 · **Revision:** 2
**Status:** Audit only — no code changes made

---

## 1. Upstream Source Files

| Type | Path | Lines | Platform |
|------|------|-------|----------|
| TaskContext | `BetterGenshinImpact/GameTask/TaskContext.cs` | 111 | Windows host |
| RunnerContext | `BetterGenshinImpact/GameTask/RunnerContext.cs` | 217 | Windows host |

---

## 2. TaskContext — Full Field & Method Audit

### 2.1 Fields & Properties

| # | Member | Type | Windows Dependency | Access Mode | Classification |
|---|--------|------|--------------------|-------------|----------------|
| 1 | `Instance()` | singleton (LazyInitializer) | None | Lifecycle | ✅ Pure C# |
| 2 | `IsInitialized` | `bool` | None | Read | ✅ Pure C# |
| 3 | `GameHandle` | `IntPtr` | **Win32 HWND** | Read | ❌ macOS uses window ID, not HWND |
| 4 | `PostMessageSimulator` | `PostMessageSimulator` | **Win32 PostMessage** | Invoke | ❌ No macOS equivalent; call site already #if guarded |
| 5 | `DpiScale` | `float` | **Win32 WPF DPI** | Read | ⚠️ **Not equivalent to `ScaleTo1080PRatio`** — see §2.4 |
| 6 | `SystemInfo` | `ISystemInfo` | Interface already cross-platform | Read | ✅ Via `MacSystemInfo` in Core |
| 7 | `Config` | `AllConfig` (20+ task configs) | References all task config classes | Read | ⚠️ Split — Core needs per-consumer accessors |
| 8 | `LinkedStartGenshinTime` | `DateTime` | None | Read/Write | ✅ Pure C# |
| 9 | `CurrentScriptProject` | `ScriptGroupProject` | ClearScript V8 | Read/Write | ⚠️ Defer — not in Core scope |

### 2.2 Methods

| # | Method | Windows Dependency | Access Mode | Classification |
|---|--------|--------------------|-------------|----------------|
| 1 | `Init(IntPtr hWnd)` | **Win32 HWND** | Lifecycle | ❌ Provide `Init(GameWindowMetrics)` for macOS |
| 2 | `GetGenshinGameProcessNameList()` | **Depends on `Config.GenshinStartConfig.InstallPath`** | Read | ⚠️ Platform-agnostic code, but requires full startup config — defer |
| 3 | `DestroyInstance()` | None | Lifecycle | ⚠️ **Shim-only** — no upstream equivalent; keep as test helper, re-evaluate when Shim deleted |

### 2.3 All Call Sites (in linked Core files)

| File:Line | Access | Access Mode | Guarded? |
|-----------|--------|-------------|----------|
| `AutoPickTrigger.cs:69` | `Config.AutoPickConfig` | Read | No |
| `AutoPickTrigger.cs:195` | `SystemInfo.AssetScale` | Read | No |
| `AutoPickTrigger.cs:196` | `Config.AutoPickConfig` | Read | No |
| `AutoPickAssets.cs:70` | `Config.AutoPickConfig.PickKey` | Read | No |
| `AutoPickAssets.cs:78` | `Config.KeyBindingsConfig` | Write | ✅ `#if BGI_FULL_WINDOWS` |
| `AutoPickAssets.cs:86` | `Config.AutoPickConfig.PickKey` | Write | No |
| `CaptureContent.cs:28` | `SystemInfo` | Read | No |
| `BaseAssets.cs:21` | `SystemInfo` (constructor) | Lifecycle | No |
| `Region.cs:99` | `PostMessageSimulator` | Invoke | ✅ `#if BGI_FULL_WINDOWS` |
| `GameCaptureRegion.cs:29,46` | `DpiScale` | Read | ✅ `#if BGI_FULL_WINDOWS` |
| `GameCaptureRegion.cs:94-111` | `SystemInfo.CaptureAreaRect` | Read | ✅ `#if BGI_FULL_WINDOWS` |
| `OcrFactory.cs:59` | `Config.OtherConfig.OcrConfig` | Read | No |
| `OcrFactory.cs:78` | `Config.OtherConfig.GameCultureInfoName` | Read | No |
| `BgiOnnxFactory.cs:75` | `Config.HardwareAccelerationConfig` | Read | OnnxFactory is Shim'ed — N/A |

**Active (unguarded) call sites: 8** — all are Read access to `SystemInfo` or `Config.AutoPickConfig`/`OtherConfig`.
**Guarded call sites: 5** — all Windows-specific (PostMessage, DPI, capture rect in overlay methods).

### 2.4 Key Semantic Clarification: DpiScale ≠ ScaleTo1080PRatio

| Concept | Meaning | Example (4K display, 1920×1080 game window) |
|---------|---------|---------------------------------------------|
| `DpiScale` | Windows desktop/WPF DPI scaling factor | 2.0 (200% scaling) |
| `ScaleTo1080PRatio` | Game capture resolution relative to 1080p baseline | 1.0 (window IS 1920 wide) |

**These are semantically distinct.** `DpiScale` is only used in Windows guarded paths (GameCaptureRegion drawing methods). The unguarded recognition code uses `ISystemInfo.ScaleTo1080PRatio` and `AssetScale` — which are already cross-platform. **Do not declare DpiScale redundant with ScaleTo1080PRatio.**

---

## 3. RunnerContext — Full Field & Method Audit

### 3.1 Fields & Properties

| # | Member | Type | Access Mode | Cross-Platform? |
|---|--------|------|-------------|-----------------|
| 1 | `Instance` | Singleton (via `Singleton<T>`) | Lifecycle | ✅ |
| 2 | `IsContinuousRunGroup` | `bool` | Read/Write | ✅ State flag |
| 3 | `taskProgress` | `TaskProgress.TaskProgress` | Read/Write | ❌ Type not linked |
| 4 | `IsSuspend` | `bool` | Read/Write | ✅ State flag |
| 5 | `IsPreExecution` | `bool` | Read/Write | ✅ State flag |
| 6 | `SuspendableDictionary` | `Dict<string, ISuspendable>` | Read/Write | ❌ `ISuspendable` not linked |
| 7 | `isAutoFetchDispatch` | `bool` | Read/Write | ✅ State flag |
| 8 | `PartyName` | `string?` | Read/Write | ✅ State flag |
| 9 | `AutoPickTriggerStopCount` | `int` | **Read** | ✅ **Only Core call site** |
| 10 | `_combatScenes` (private) | `CombatScenes?` | Read/Write | ❌ Not linked (AutoFight) |

### 3.2 Methods

| # | Method | Lines | Core Relevance | Thread Safety Notes |
|---|--------|-------|---------------|---------------------|
| 1 | `GetCombatScenes()` | 64-83 | ❌ AutoFight only | — |
| 2 | `TrySyncCombatScenesSilent()` | 88-105 | ❌ AutoFight only | — |
| 3 | `ClearCombatScenes()` | 107-110 | ❌ | — |
| 4 | `Clear()` | 115-127 | ⚠️ Task lifecycle — defer | — |
| 5 | `Reset()` | 132-143 | ⚠️ Task lifecycle — defer | — |
| 6 | `StopAutoPick(int)` | 148-153 | ⚠️ See §3.3 | Non-atomic `++`, no CancellationToken |
| 7 | `ResumeAutoPick(int)` | 157-194 | ⚠️ See §3.3 | Spawns `new Thread` with `Thread.Sleep(1000)` |
| 8 | `StopAutoPickRunTask(Func<Task>, int)` | 200-212 | ⚠️ See §3.3 | Wraps `StopAutoPick`/`ResumeAutoPick` |
| 9 | `stop()` | 213-216 | ❌ AutoFight only | — |

### 3.3 Thread Safety Warnings

`StopAutoPick()` and `ResumeAutoPick()` are platform-agnostic C# but have known issues:
- `AutoPickTriggerStopCount++` is **not atomic** (not `Interlocked.Increment`)
- `ResumeAutoPick()` spawns a **bare `new Thread`** with no `CancellationToken`
- Thread spins with `Thread.Sleep(1000)` — cannot be cancelled or joined
- No centralized lifecycle management

**Recommendation:** These methods can be kept with upstream semantics in a Windows/Windows host. For Core, the current single call site only **reads** `AutoPickTriggerStopCount`. Do not default to full migration of the coordination methods — provide only the field or a minimal `IAutoPickRuntimeState` interface until usage evidence demands more.

### 3.4 All Call Sites (in linked Core files)

| File:Line | Access | Access Mode |
|-----------|--------|-------------|
| `AutoPickTrigger.cs:164` | `AutoPickTriggerStopCount` | Read |

---

## 4. Config Access Pattern

| Config Property | Accessed From | Access Mode |
|----------------|---------------|-------------|
| `AutoPickConfig` | AutoPickTrigger, AutoPickAssets | Read |
| `AutoPickConfig.PickKey` | AutoPickAssets | Read / Write |
| `KeyBindingsConfig.PickUpOrInteract` | AutoPickAssets | Write (guarded) |
| `OtherConfig.OcrConfig` | OcrFactory | Read |
| `OtherConfig.GameCultureInfoName` | OcrFactory | Read |
| `HardwareAccelerationConfig` | BgiOnnxFactory (shim'ed) | N/A |

Consumers are isolated: AutoPick uses `AutoPickConfig`, OCR uses `OtherConfig+OcrConfig`. No consumer needs ALL config at once. This supports per-consumer interfaces.

---

## 5. Shim vs Upstream — Delta

### TaskContext

| Feature | Upstream | Shim | Verdict |
|---------|----------|------|---------|
| Singleton | `LazyInitializer` | Manual lock | Minor — not harmful |
| `Config` type | `AllConfig` | `CoreConfig` (AutoPick + OtherConfig) | **Shim under-scoped** |
| `Init()` | `Init(IntPtr hWnd)` | `Init(GameWindowMetrics)` | Platform-agnostic — correct direction |
| `GameHandle` | Exposed | Missing | Intentionally omitted — correct |
| `PostMessageSimulator` | Exposed | Missing | Windows-only, guarded call sites |
| `DpiScale` | Exposed | Missing | Not equivalent to ScaleTo1080PRatio (§2.4); unguarded path doesn't need it |
| `GetGenshinGameProcessNameList()` | Full impl (requires `GenshinStartConfig.InstallPath`) | Missing | Depends on full Config — not portable yet |
| `DestroyInstance()` | Not in upstream | Present | **Shim-only test helper** — re-evaluate when Shim deleted |

### RunnerContext

| Feature | Upstream | Shim | Verdict |
|---------|----------|------|---------|
| `AutoPickTriggerStopCount` | Field + coordination methods | Field only | **Shim under-scoped** — coordination methods exist but have thread safety concerns (§3.3) |
| All other fields | 13 fields, 6 methods | None | Not in current Core scope |

---

## 6. Dependency Classification

### Already Cross-Platform (in Core via ISystemInfo / BgiRect)
- `SystemInfo` (via `MacSystemInfo`)
- `AssetScale`, `ScaleTo1080PRatio`, `CaptureAreaRect` (via `ISystemInfo`)

### Platform-Agnostic But Needs Full Config (defer)
- `GetGenshinGameProcessNameList()` → requires `Config.GenshinStartConfig.InstallPath`
- `Config.OtherConfig.OcrConfig` → partially available via linked `OtherConfig.cs`

### Windows-Only — Already Guarded or Abstracted
- `GameHandle` → macOS uses window ID, not HWND
- `PostMessageSimulator` → #if guarded at single call site
- `DpiScale` → #if guarded at drawing call sites; not needed in recognition path

### Not in Core Scope
- `CurrentScriptProject`, `CombatScenes`, `TaskProgress`, `ISuspendable`
- `HardwareAccelerationConfig`, `KeyBindingsConfig`

---

## 7. Initialization Flow

### Windows (Current)

```
App.OnStartup
  → TaskTriggerDispatcher.Start(IntPtr hWnd, ...)
    → TaskContext.Instance().Init(hWnd)
      → GameHandle = hWnd
      → PostMessageSimulator = Simulation.PostMessage(hWnd)
      → SystemInfo = new SystemInfo(hWnd)
      → DpiScale = DpiHelper.ScaleY
      → IsInitialized = true
    → GameCapture.Start(hWnd, ...)
    → Triggers = LoadInitialTriggers()
```

### macOS (Desired — Approach B: Adapter, not Shim)

```
Swift Host (MacGI / BetterGI.Mac.Runtime)
  → Enumerate game window → obtain window ID + metrics
  → Create MacSystemInfo from metrics
  → Create runtime providers (AutoPickConfig, OCR config)
  → Create MacRuntimeAdapter(systemInfo, configProviders)
  → Register adapter with Core composition root
  → Set PlatformServices.Input = MacInputBackend
  → Set DesktopRegion.DisplayWidth/Height from screen metrics
  → Start capture backend (ScreenCaptureKit)
  → Load triggers → begin dispatcher tick loop
```

Key differences from Windows:
- No `TaskContext.Instance().Init()` call — adapter replaces the Shim
- No HWND, no DPI, no PostMessage
- `SystemInfo` created from `GameWindowMetrics`, not Win32 APIs
- Config providers injected, not accessed via static `TaskContext.Instance().Config`
- Init sequence does NOT use the Shim's `Init(GameWindowMetrics)` as a long-term API



## 8. Interface Design: Per-Consumer with Correct Layering

### ❌ Wrong Placement: Platform.Abstractions

```csharp
// These reference AutoPickConfig, OtherConfig, ISystemInfo — all Core/business types.
// Putting them in Platform.Abstractions creates:
//   Core → Platform.Abstractions → Core   (circular dependency)
public interface IAutoPickConfigProvider { ... }  // DON'T put here
```

### ✅ Correct Placement: Core Internal Abstractions

```
BetterGenshinImpact.Core/
  Abstractions/
    Runtime/
      IAutoPickConfigProvider.cs
      IOcrRuntimeConfigProvider.cs
      IAutoPickRuntimeState.cs
```

Dependency direction:
```
Core consumers
  → Core/Abstractions/Runtime/  (business runtime interfaces)
  → Platform.Abstractions/      (platform capability interfaces)

Windows/macOS adapters
  → Core/Abstractions/Runtime/  (implement these)
  → Platform.Abstractions/      (use these)
```

No circular dependency. `Platform.Abstractions` stays pure: input, window, capture, user interaction, BgiRect, BgiKey.

### Per-Consumer Interfaces (final)

```csharp
// Core/Abstractions/Runtime/IAutoPickConfigProvider.cs
public interface IAutoPickConfigProvider
{
    /// <summary>Read current pick key. May be changed by consumer in error-recovery path.
    /// AutoPickAssets writes "F" back on custom-key load failure — consumers
    /// that only read must tolerate the property being writable.</summary>
    AutoPickConfig AutoPickConfig { get; }
}

// Core/Abstractions/Runtime/IOcrRuntimeConfigProvider.cs
public interface IOcrRuntimeConfigProvider
{
    /// <summary>PaddleOCR model configuration (model paths, version).</summary>
    PaddleOcrModelConfig PaddleModel { get; }

    /// <summary>Game culture info name for OCR language selection.</summary>
    string GameCultureInfoName { get; }
}

// Core/Abstractions/Runtime/IAutoPickRuntimeState.cs
public interface IAutoPickRuntimeState
{
    /// <summary>Stop count > 0 means picking is paused. Read-only for AutoPickTrigger.</summary>
    int StopCount { get; }
}
```

### Why IGameSystemInfoProvider is NOT needed

`ISystemInfo` already exists as a cross-platform interface (§2.1, item 6). Consumers (CaptureContent, BaseAssets) already depend on it directly. Adding a provider wrapper around it adds indirection without abstraction benefit. Keep `ISystemInfo` as-is.

### Why IOcrRuntimeConfigProvider exposes minimal values, not ObservableObject

The upstream `OtherConfig.Ocr` inherits `ObservableObject` (UI databinding). It carries WPF change-notification baggage irrelevant to Core. The runtime contract should expose only the concrete values OCR actually reads — `PaddleOcrModelConfig` and `GameCultureInfoName`. The adapter maps from the full config object.

### AutoPickConfig Write Semantics

`AutoPickAssets.cs:86` writes `AutoPickConfig.PickKey = "F"` when custom key loading fails. This is a **persistent config mutation** — the consumer changes the config state as an error-recovery fallback.

The interface's `AutoPickConfig` property must remain the **same mutable reference** as the upstream config object. The adapter must not return a defensive copy. This preserves the upstream behavior without changing business logic.

This is a design decision, not a bug: the interface exposes writable config intentionally.



## 9. Migration Approach Comparison

| Criterion | Approach A: Modify Upstream | Approach B: Core Adapter/Provider |
|-----------|----------------------------|----------------------------------|
| Diff size on upstream files | Larger — adds interface implementation | Smaller — no upstream mods |
| Merge conflict risk (fork) | **High** | **Low** |
| Call site changes | None (same `TaskContext.Instance()`) | Moderate (replace static access with injection) |
| Long-term maintainability | Simpler initial code, harder rebase | More initial wiring, easier rebase |
| Testability | Hard (static singleton) | Easy (injectable interface) |

**Recommendation: Approach B.** Keep upstream TaskContext/RunnerContext untouched. Create adapter classes in Core that implement the per-consumer interfaces, delegating to the real upstream types on Windows and to Core-native implementations on macOS.

### Injection Strategy

**Priority 1: Constructor injection.** Each consumer receives its dependencies explicitly:
```csharp
public AutoPickTrigger(IAutoPickConfigProvider config, IAutoPickRuntimeState state, ...)
```

**Priority 2: Replaceable runtime service registry.** If upstream construction chains make constructor injection infeasible (e.g., many task types with deep inheritance), use a scoped service container with fallback adapters. This must be explicitly replaceable — not a hidden static singleton.

**Banned: Non-replaceable static global gateway.** Do not create `CoreServices.AutoPickConfig` or equivalent static singletons. That just recreates `TaskContext.Instance()` under another name.



## 10. Recommended Migration Order (Revised)

### Phase A: Interface Extraction

1. Create directory `BetterGenshinImpact.Core/Abstractions/Runtime/`
2. Define `IAutoPickConfigProvider` in that directory
3. Define `IOcrRuntimeConfigProvider` in that directory
4. Define `IAutoPickRuntimeState` in that directory
5. Verify Shims can satisfy these interfaces (read-only check)
6. **Do not** define `ITaskContextCore` or `IGameSystemInfoProvider`
7. **No files added to `Platform.Abstractions/`**

### Phase B: Adapter Implementation

8. Create `MacCoreRuntimeAdapter` — implements all three interfaces using current Shim types (`MacSystemInfo` + `CoreConfig`)
9. Create `WindowsCoreRuntimeAdapter` — implements all three interfaces backed by real upstream `TaskContext` (not linked into Core yet — lives in Windows host project)
10. Wire `AutoPickTrigger` constructor to accept `IAutoPickConfigProvider` + `IAutoPickRuntimeState` via constructor injection
11. Wire `OcrFactory` to accept `IOcrRuntimeConfigProvider` via constructor injection
12. CaptureContent/BaseAssets continue using `ISystemInfo` directly (no wrapper needed)

### Phase C: Shim Deletion

13. Delete `Shim/TaskContext.cs`, `Shim/RunnerContext.cs`, `CoreConfig`
14. Core now uses authentic upstream config/logic through adapters — no parallel implementations

### What NOT to Do
- ❌ Do not add `#if BGI_FULL_WINDOWS` to upstream TaskContext
- ❌ Do not expand Shim CoreConfig with more hand-written config stubs
- ❌ Do not delete upstream members to make it compile on macOS
- ❌ Do not create parallel TaskContext/RunnerContext with same name in another namespace
- ❌ Do not declare DpiScale equivalent to ScaleTo1080PRatio
- ❌ Do not promote `DestroyInstance()` to a permanent interface
- ❌ Do not put runtime business interfaces in `Platform.Abstractions/` (circular dep)
- ❌ Do not use static global singletons for dependency injection



## 11. Current Shim Retention Justification

| Shim File | Reason to Keep (short-term) | Long-term Disposition |
|-----------|-----------------------------|----------------------|
| `TaskContext.cs` | Provides AutoPick with `SystemInfo` + `Config.AutoPickConfig` access | Delete after Phase C |
| `RunnerContext.cs` | Provides `AutoPickTriggerStopCount` (read-only) | Delete after Phase C |
| `CoreConfig` | Avoids linking full `AllConfig` with 20+ task config types | Delete after Phase C |
| `DestroyInstance()` | Test helper — resets singleton between test runs | Delete with Shim |

---

## 12. Related Audit: Region Chain (Completed)

Region/DesktopRegion/GameCaptureRegion: ✅ Real upstream files now linked.
Drawing/mouse methods guarded with minimal `#if BGI_FULL_WINDOWS`.
Core recognition path (Find, Derive, ConvertRes, coordinate transforms) is 100% authentic upstream code.

---

## 13. Phase A Task Checklist

| # | Task | Files Affected | Prerequisites |
|---|------|---------------|---------------|
| A1 | Create `Core/Abstractions/Runtime/` directory | `BetterGenshinImpact.Core/` | None |
| A2 | Define `IAutoPickConfigProvider` (with write-semantics doc) | `Core/Abstractions/Runtime/` | A1 |
| A3 | Define `IOcrRuntimeConfigProvider` (PaddleModel + CultureInfo only) | `Core/Abstractions/Runtime/` | A1 |
| A4 | Define `IAutoPickRuntimeState` (StopCount read-only) | `Core/Abstractions/Runtime/` | A1 |
| A5 | Verify existing Shims satisfy A2-A4 signatures | Read-only check | A2-A4 |
| A6 | Confirm no files added to `Platform.Abstractions/` | `Platform.Abstractions/` | A1-A5 |
| A7 | Propose Phase B adapter design | Design doc | A5 |
| A8 | No code changes to upstream TaskContext/RunnerContext | — | All above |

### Phase A Outcome: Interfaces Defined

Three interfaces created in `BetterGenshinImpact.Core/Abstractions/Runtime/`:
- `IAutoPickConfigProvider` — returns mutable `AutoPickConfig` reference (preserves write-back semantics)
- `IOcrRuntimeConfigProvider` — `PaddleOcrModelConfig + GameCultureInfoName` only (no ObservableObject)
- `IAutoPickRuntimeState` — read-only `int StopCount`

Build: 0 errors. Verification: 15/15 passed. No consumers modified.

### Phase B Preview: OCR Dependency Notes

Even with `IOcrRuntimeConfigProvider` injected, `OcrFactory` still contains two static service locator calls:
```
App.ServiceProvider.GetRequiredService<OcrFactory>()
App.ServiceProvider.GetRequiredService<BgiOnnxFactory>()
```
These must be addressed separately in Phase B — configuration injection alone does not eliminate global state. Documented for follow-up.
