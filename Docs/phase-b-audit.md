# Phase B Construction Chain Audit (Revised)

**Branch:** `mac-core-extraction` (commit `790225b`)
**Status:** Audit only — no code changes.

---

## 1. Two GameTaskManagers — Must NOT Be Confused

| Aspect | Windows Upstream (`BetterGenshinImpact/`) | Core Shim (`BetterGenshinImpact.Core/Shim/`) |
|--------|-----------------------------------------|---------------------------------------------|
| Type | `internal class GameTaskManager` | `public static class GameTaskManager` |
| LoadInitialTriggers | ✅ Yes — creates all triggers, including `new AutoPickTrigger()` | ❌ Not present |
| AddTrigger / LoadAssetImage | Both methods available | Only `LoadAssetImage` — trigger creation NOT in Core Shim |

**Key implication:** macOS Core does NOT call `LoadInitialTriggers()`. The statement "both Windows dispatcher and macOS runtime call this" is unproven. The macOS runtime needs its own trigger composition path, or must link GameTaskManager.

### macOS AutoPickTrigger Creation Sites (to be verified)

| Site | Existence | Notes |
|------|-----------|-------|
| Swift bridge | Unknown — not yet built | Likely wraps .NET dispatcher |
| macOS dispatcher | Unknown | Not yet implemented |
| Verification test | No | Current test creates RecordingInputBackend + DesktopRegion directly, no trigger |

**Conclusion:** macOS has no trigger-creation code yet. The planned `MacRuntimeAdapter` + composition root will be this code. Do not assume shared entry point with Windows.

---

## 2. AutoPickAssets — Must Be Addressed, Not Skiped

Current document said:

> Adapters do NOT need to change AutoPickAssets. It already accesses config through `TaskContext.Instance()`.

This is **wrong**. It contradicts Phase C (delete Shim). If AutoPickAssets continues to call `TaskContext.Instance().Config`, deleting the Shim breaks it.

### Consumer Analysis

All 8 call sites access `AutoPickAssets.Instance`, which calls `TaskContext.Instance().Config.AutoPickConfig` in its constructor.

AutoPickAssets has a **private** constructor (CRTP singleton pattern: `BaseAssets<AutoPickAssets>` via `Singleton<T>`).
Normal constructor injection is not possible without breaking the singleton base.

### Recommended: Configure() — But Constructor Must Be Split

The current private constructor reads config immediately:
```csharp
private AutoPickAssets()
{
    var keyName = TaskContext.Instance().Config.AutoPickConfig.PickKey;
    // LoadCustomPickKey, PickVk mapping, ChatPickRo ...
}
```

This means `Configure()` called AFTER `Instance` first access is **too late**. The
constructor has already read `TaskContext.Instance()` before `Configure()` runs.

**Required refactoring:**

1. Private constructor initializes only config-independent template assets:
```csharp
private AutoPickAssets()
{
    FRo = new RecognitionObject { ... template only, no config ... };
    ChatIconRo = new RecognitionObject { ... };
    SettingsIconRo = new RecognitionObject { ... };
    LRo = new RecognitionObject { ... };
    // NO PickKey, NO PickVk, NO ChatPickRo here
}
```

2. All config-dependent initialization moves to `Configure()`:
```csharp
public void Configure(IAutoPickConfigProvider provider)
{
    if (_configured)
        throw new InvalidOperationException("AutoPickAssets is already configured.");
    _configProvider = provider;
    var keyName = provider.AutoPickConfig.PickKey;
    PickRo = LoadCustomPickKey(keyName);
    PickVk = BgiKeyMapper.ToKey(keyName);
    ChatPickRo = LoadCustomChatPickKey(keyName);
    _configured = true;
}
```

3. `PickVk` and `PickRo` remain mutable (fields, not readonly) since they are
   now set in `Configure()`, not the constructor.

| Property | Value |
|----------|-------|
| Invoked by | Composition root, immediately after `AutoPickAssets.Instance` first access |
| Must complete before | First `OnCapture()` call |
| Constructor scope | Template assets only — no config reads |
| Fallback to TaskContext? | No — fail fast if unconfigured |
| Test reset | `AutoPickAssets.DestroyInstance()` + re-`Configure()` — not `TaskContext.DestroyInstance()` |

### Concrete Code Migration (AutoPickAssets.cs)

Lines to **move** from constructor to `Configure()`:

| Line | Content | New Home |
|------|---------|----------|
| `var keyName = TaskContext.Instance().Config.AutoPickConfig.PickKey` | Config read | `Configure()` |
| `PickVk = BgiKeyMapper.ToKey(keyName)` | Key mapping | `Configure()` |
| `PickRo = LoadCustomPickKey(keyName)` | Custom key asset | `Configure()` |
| `ChatPickRo = LoadCustomChatPickKey(keyName)` | Chat key asset | `Configure()` |
| `PickKey = "F"` write-back on failure | Config fallback | `Configure()` |
| `TaskContext.Instance().Config.AutoPickConfig.KeyBindingsConfig...` (guarded) | Setter | `Configure()`, still guarded |

### Long-term evaluation: split template assets from runtime config

```csharp
// Template-only singleton (no config dependency)
AutoPickTemplateAssets : Singleton<AutoPickTemplateAssets>

// Runtime config object (explicitly constructed)
AutoPickRuntimeAssets(IAutoPickConfigProvider provider)
```

This separation aligns with broader migration — template matching assets are truly
singleton; key bindings and runtime behavior are per-context. But it's a larger
refactor than Phase B requires. The Configure() approach is sufficient for Phase B.

---

## 3. MacCoreRuntimeAdapter Must Cover All Three Interfaces

Phase A defined three interfaces:
- `IAutoPickConfigProvider` — AutoPick configuration
- `IOcrRuntimeConfigProvider` — OCR configuration
- `IAutoPickRuntimeState` — read-only `StopCount`

The adapter must provide **all three**, either as a single class or separate:
```csharp
class MacCoreRuntimeAdapter : IAutoPickConfigProvider, IOcrRuntimeConfigProvider { ... }
class MacAutoPickRuntimeState : IAutoPickRuntimeState { ... }
```

Do not rely on `RunnerContext.Instance()` after Phase C.

### Adapter Input — No Redundancy

**Avoid:** passing both `OtherConfig.Ocr` and `PaddleOcrModelConfig` — the former already contains the latter.

**Choose one:**
- **Option A (minimal):** `MacCoreRuntimeAdapter(AutoPickConfig, PaddleOcrModelConfig, string cultureInfo, IAutoPickRuntimeState)`
- **Option B (full config):** `MacCoreRuntimeAdapter(AutoPickConfig, OtherConfig.Ocr, IAutoPickRuntimeState)` — adapter maps to interface internally

**Recommendation:** Option A — adapter receives only what the three interfaces expose. No redundant parameters.

---



## 4. Cross-Project Interface Sharing — Structural Problem

### The Problem

Phase A placed three interfaces in `BetterGenshinImpact.Core/Abstractions/Runtime/`.

Windows host (`BetterGenshinImpact.csproj`) does NOT reference `BetterGenshinImpact.Core`.
If it did, both assemblies would contain same-namespace types (AutoPickConfig, OcrFactory,
TaskContext, etc.) — creating **type identity conflicts** and unresolvable ambiguity.

Therefore:
- ❌ B1 cannot place `WindowsAutoPickConfigProvider` in Core and register it in App.xaml.cs
- ❌ B2 cannot modify OcrFactory in the upstream project while depending on an interface
      only visible in the Core assembly
- ❌ Windows DI cannot reference types from Core assembly

### Solution: Shared Source (Not Shared Assembly)

Move interface files into the upstream source tree, so BOTH projects compile them
independently — each into its own assembly. No assembly-to-assembly dependency.

**New file location:**
```
BetterGenshinImpact/Core/Abstractions/Runtime/
  IAutoPickConfigProvider.cs
  IOcrRuntimeConfigProvider.cs
  IAutoPickRuntimeState.cs
```

**Windows host:** Default `EnableDefaultCompileItems` (true) — auto-compiled.
**Core:** `EnableDefaultCompileItems` is `false` — explicit `Compile Include` with `Link`:
```xml
<Compile Include="../BetterGenshinImpact/Core/Abstractions/Runtime/IAutoPickConfigProvider.cs"
         Link="Core/Abstractions/Runtime/IAutoPickConfigProvider.cs" />
```

**Delete** the old copies in `BetterGenshinImpact.Core/Abstractions/Runtime/`.

**Windows providers** live in `BetterGenshinImpact/Core/Runtime/Windows/` (Windows project).
**Mac providers** live in `BetterGenshinImpact.Core/Adapters/` (Core project).

### Type Identity

Both assemblies compile the same `.cs` files — the interface types exist in each assembly
independently. Consumers in Windows see `Windows.BetterGenshinImpact.Core.Abstractions.Runtime.IAutoPickConfigProvider`.
Consumers in Core see `Core.BetterGenshinImpact.Core.Abstractions.Runtime.IAutoPickConfigProvider`.
They are different .NET types (different assembly). This is OK — there is **no shared assembly
boundary** where type identity must match. Each host wires its own providers independently.

---

## 5. Static Gateway Is Banned — All References Deleted

Revision 3 prohibits: non-replaceable static global gateway.

The following suggestions from the previous document are **removed**:
- ❌ "static gateway" — prohibited
- ❌ "optional static method or thread-local" — prohibited
- ❌ "keep parameterless constructor but populate providers via static gateway" — prohibited
- ❌ "pre-populated container" — unacceptably ambiguous

### Allowed only:
- Constructor injection (preferred)
- Explicit factory parameter when constructor injection is infeasible
- Host composition root creates and wires dependencies — dispatcher consumes them

---

## 6. OCR Config vs OCR Service — Must Not Be Confused

The previous document conflated:
- **IOcrRuntimeConfigProvider** — provides model config (PaddleOcrModelConfig + CultureInfo)
- **OcrFactory.Paddle** — returns `IOcrService` instance for running OCR

IOcrRuntimeConfigProvider does NOT replace OcrFactory.Paddle. Two separate dependencies:

### OCR Dependency Paths

```
OcrFactory (DI singleton)
  ├─ requires: IOcrRuntimeConfigProvider  (model type + culture)
  ├─ requires: BgiOnnxFactory             (ONNX inference session)
  └─ provides: IOcrService via OcrFactory.Paddle static
       └─ consumed by: AutoPickTrigger, AutoBoss, AutoFight, ...

PickTextInference
  └─ requires: BgiOnnxFactory             (ONNX inference session)
```

### Phase B Scope for OCR

| Dependency | Phase B Treatment |
|------------|-------------------|
| `IOcrRuntimeConfigProvider` → OcrFactory constructor | Add as constructor parameter |
| `BgiOnnxFactory` → OcrFactory/PickTextInference | Keep as DI-injected; not a config concern |
| `OcrFactory.Paddle` static → callers | Defer — 20+ call sites, large blast radius |

Result: OcrFactory takes `IOcrRuntimeConfigProvider` in constructor. `PaddleOcrService` keeps getting `BgiOnnxFactory` from DI. `OcrFactory.Paddle` static remains untouched in Phase B.

---

## 7. Global Dependencies: Precise Counting

| Category | Count | Locations |
|----------|-------|-----------|
| `App.ServiceProvider.GetRequiredService<T>()` | **3** | OcrFactory.Paddle, OcrFactory.CreatePaddleOcr (2×), PickTextInference ctor |
| `TaskContext.Instance().Config.*` — static singleton | **4 active in Core** | AutoPickTrigger:2, AutoPickAssets:2 |
| `RunnerContext.Instance` — static singleton | **1 active in Core** | AutoPickTrigger:1 |

**Do not merge these counts.** Different remedies needed:
- `App.ServiceProvider` → constructor injection or factory
- `TaskContext/RunnerContext` → per-consumer interfaces + adapter

---

## 8. Composition Root Location

### Correct assignment:

| Platform | Composition Root | Responsibility |
|----------|-----------------|----------------|
| Windows | `App.OnStartup` + DI container | Registers all services, creates dispatcher |
| macOS | Swift bridge + .NET runtime bootstrap | Creates adapters, configures providers, creates dispatcher |

**Dispatcher:** Receives fully-assembled dependencies. Does NOT create adapters or register services. Its job is to run the tick loop.

---

## 9. Revised Phase B Steps (B1-B8)

Each step must:
- Compile and pass 15/15 at every step
- Include host-specific wiring (DI registration, adapter creation, test harness update)
- Not introduce unregistered service dependencies

### B1: Move interfaces to shared upstream source tree

| Action | Notes |
|--------|-------|
| Move `IAutoPickConfigProvider.cs` | From `Core/Abstractions/Runtime/` → `BetterGenshinImpact/Core/Abstractions/Runtime/` |
| Move `IOcrRuntimeConfigProvider.cs` | Same |
| Move `IAutoPickRuntimeState.cs` | Same |
| Add `Compile Include` with `Link` to Core csproj | 3 entries |
| Delete old copies in `Core/Abstractions/Runtime/` | Remove directory |
| Verify `dotnet build` | Both src trees compile the same interface |

**No consumer changes. No new types. Just file relocation.**

### B2: Windows providers + DI registration

| File | Location | Change |
|------|----------|--------|
| `WindowsAutoPickConfigProvider.cs` | `BetterGenshinImpact/Core/Runtime/Windows/` | New — wraps `TaskContext.Instance().Config.AutoPickConfig` |
| `WindowsOcrRuntimeConfigProvider.cs` | Same | New — wraps `TaskContext.Instance().Config.OtherConfig` |
| `WindowsAutoPickRuntimeState.cs` | Same | New — wraps `RunnerContext.Instance` |
| `App.xaml.cs` | DI registration | Register all three as singletons |

**No consumer changes. DI registrations don't change runtime behavior.**

### B3: macOS providers + Verification wiring

| File | Location | Change |
|------|----------|--------|
| `MacCoreRuntimeAdapter.cs` | `Core/Adapters/` | Implements `IAutoPickConfigProvider` + `IOcrRuntimeConfigProvider`; input: `(AutoPickConfig, PaddleOcrModelConfig, string cultureInfo)` |
| `MacAutoPickRuntimeState.cs` | `Core/Adapters/` | Implements `IAutoPickRuntimeState` |
| `Program.cs` (Verification) | Test harness | Wire MacCoreRuntimeAdapter into existing tests |

**Verification must still pass 15/15 after wiring.**

### B4: OcrFactory — inject IOcrRuntimeConfigProvider

- Add `IOcrRuntimeConfigProvider` to `OcrFactory` constructor
- Replace `GetConfig()` body with provider access
- Must include in same commit: Windows DI registration update (App.xaml.cs), macOS adapter wiring (Verification)

### B5: AutoPickTrigger — inject IAutoPickRuntimeState

- Add constructor overload `AutoPickTrigger(IAutoPickRuntimeState)`
- Parameterless constructor keeps `RunnerContext.Instance` (Windows backward compat)
- macOS trigger creation uses new overload

### B6: AutoPickAssets — split constructor + Configure()

As described in §2. Config-dependent logic moves from constructor to `Configure(IAutoPickConfigProvider)`.
Fail fast if `OnCapture` called before `Configure`.

### B7: macOS trigger factory / composition root

- `MacTriggerFactory` creates triggers with macOS wiring
- macOS bootstrap calls factory, then dispatcher
- Windows unchanged

### B8: Delete Shim files

**Gate:** Direct caller count must reach zero. Verify with:

```bash
rg 'TaskContext\.Instance\(' BetterGenshinImpact/GameTask/AutoPick/ BetterGenshinImpact/GameTask/CaptureContent.cs BetterGenshinImpact/GameTask/Model/BaseAssets.cs BetterGenshinImpact/Core/Recognition/OCR/OcrFactory.cs
rg 'RunnerContext\.Instance' BetterGenshinImpact/GameTask/AutoPick/
rg -l 'Shim/TaskContext\|Shim/RunnerContext\|Shim/CoreConfig' BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj
```

Delete only when all three searches return zero results in the linked-file set.

| File | Condition to Delete |
|------|---------------------|
| `Shim/TaskContext.cs` | Zero linked files access `TaskContext.Instance()` for AutoPick/OCR config |
| `Shim/RunnerContext.cs` | Zero linked files access `RunnerContext.Instance` |
| `Shim/CoreConfig.cs` | Shim/TaskContext CSproj reference removed |

---

## Summary: Phase B Feasibility

| Step | Scope | Dependency |
|------|-------|------------|
| B1 | Interface file relocation — no consumer changes | None (Phase A complete) |
| B2 | Windows providers + DI — no consumer changes | B1 (interfaces must be visible) |
| B3 | macOS providers + Verification wiring — no consumer changes | B1 |
| B4 | OcrFactory ctor + provider injection | B2+B3 (both providers must exist) |
| B5 | AutoPickTrigger overload + runtime-state injection | B3 (mac state must exist) |
| B6 | AutoPickAssets constructor split + Configure() | B3 (mac config provider must exist) |
| B7 | macOS trigger factory | B4-B6 (consumers must work) |
| B8 | Delete Shim files | All above (caller count = 0) |

B1-B3 are parallel (no shared dependency). B4-B6 depend on B2+B3. B7 depends on B4-B6. B8 is terminal.

---

## 9. Service Locator Cleanup — Deferred to Phase C

These are NOT addressed in Phase B:
- `OcrFactory.Paddle` static (20+ call sites in Windows host)
- `PickTextInference` constructor (uses `App.ServiceProvider.GetRequiredService<BgiOnnxFactory>()`)

Phase C will:
- Replace `OcrFactory.Paddle` static with injected `IOcrService`
- Inject `BgiOnnxFactory` into `PickTextInference`
- Remove `App.ServiceProvider` calls from recognition code

Phase B's goal is to **add config providers** — not eliminate all service locators.

| Step | Scope | Existing Prerequisite |
|------|-------|----------------------|
| B1 | Provider impl + DI registration (no consumer changes) | Phase A interfaces |
| B2 | OcrFactory ctor + IOcrRuntimeConfigProvider | B1 (Windows provider must exist) |
| B3 | AutoPickTrigger new overload + IAutoPickRuntimeState | B1 (Windows state provider must exist) |
| B4 | AutoPickAssets.Configure() | B1 (config provider must exist) |
| B5 | MacCoreRuntimeAdapter + trigger factory | B2-B4 (consumer changes must work first) |
| B6 | Delete Shim files | All above (direct caller count = 0) |

B1-B6 are **sequential**, not independent. B2 depends on B1 (Windows provider must be registered). B5 depends on B2-B4 (consumer changes must compile). B6 is gated on zero direct callers across all prior steps.
