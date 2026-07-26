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
| Must complete before | First access to `PickRo`/`PickVk` by any caller (AutoPickTrigger.Init, BvSimpleOperation, etc.) |
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
| `TaskContext.Instance().Config.KeyBindingsConfig...` (guarded) | Setter | `Configure()`, still guarded |

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

## 9. Revised Phase B Steps (B1-B10)

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
Fail fast if config-dependent fields (`PickRo`, `PickVk`) accessed before `Configure`.

### B7: macOS composition root

- `Core/Composition/MacAutoPickComposition.cs` — one-shot composition of AutoPickTrigger
- Four-state state machine (NotComposed → Composing → Composed/→ Failed)
- lock synchronization; null args validated before state change
- AutoPickTrigger receives IAutoPickConfigProvider; Init config lookup avoids TaskContext
- No IDisposable; internal ResetForVerification() for tests only
- **Init completed:** construction + Init config lookup are TaskContext-free.
  **OnCapture not covered:** still accesses TaskContext.Instance().SystemInfo.AssetScale
  and TaskContext.Instance().Config.AutoPickConfig offsets (B8+ scope).
- **Platform input not covered:** Simulation.SendInput still Win32 (B8+ scope).

### B8: AutoPickTrigger.OnCapture platform dependency extraction

**Sub-phases** — each audited separately; do NOT rewrite OnCapture in one pass:

#### B8.1: Input sends → injected IInputBackend

- `Simulation.SendInput.Keyboard.KeyPress(PickVk)` (lines 210, 257, 355, 386)
- `Simulation.SendInput.Mouse.VerticalScroll(2)` (line 198)
- Goal: AutoPickTrigger receives explicit `IInputBackend` via constructor injection
- Do NOT replace one static gateway (`Simulation.SendInput`) with another (`PlatformServices.Input`)
- Windows transition: audit all trigger creation paths; prefer all callers inject explicitly (option B)

#### B8.2: Capture metrics / AssetScale → existing ISystemInfo

- `TaskContext.Instance().SystemInfo.AssetScale` (line 214)
- Inject existing `ISystemInfo` into AutoPickTrigger
- Do NOT create `ISystemInfoProvider` — that only wraps the existing interface
- If audit reveals AutoPick needs only `AssetScale`, a narrower `IAutoPickCaptureMetrics` may be warranted; default to injecting `ISystemInfo` directly

#### B8.3: Runtime AutoPickConfig reads → existing IAutoPickConfigProvider

- `TaskContext.Instance().Config.AutoPickConfig` offsets (lines 215, 227-228, 276-277)
- `config.WhiteListEnabled`, `config.BlackListEnabled`, `config.OcrEngine`
- Already injected via `_configProvider`; simply read from it in OnCapture() too
- Transition: decide whether `_configProvider` becomes required (option B) or keeps `?? TaskContext...` fallback (option A). Audit before deciding.
- Do NOT snapshot AutoPickConfig — config may change at runtime

**Each sub-phase constraint:**
- Windows behavior unchanged
- macOS wired through injected dependency, no static fallback
- No static gateways; no OCR/Yap changes
- Verification per sub-phase

### B9: Remaining static gateways / file and UI abstractions

*(Interface names below are **provisional placeholders**. Implementation must start from real call-site needs, not create broad service interfaces directly.)*

- OcrFactory.Paddle static → injected `IOcrService` or `IPaddleOcrService` (audit needed: Ocr, OcrWithoutDetector, which call sites)
- TextInferenceFactory static → injected `ITextInference` or `IPickTextInference` (audit needed: AutoPick only uses Pick.Inference)
- Global.ReadAllTextIfExist → `IAssetReader` or `IConfigFileService` (audit needed: read-only text vs JSON deserialization vs path resolution)
- ThemedMessageBox → `IUserInteractionService` (audit needed: error only, or confirm/cancel patterns)
- Do NOT yet delete Shims

### B10: Final Shim deletion

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
| B6 | AutoPickAssets constructor split + Configure() | B2+B3 (config provider + mac adapter) |
| B7 | macOS composition root + AutoPickTrigger provider injection | B4-B6 (consumers must work) |
| B8 | OnCapture platform dependency extraction | B7 (trigger must be composable) |
| B9 | Static gateways + file/UI abstractions | B7 (trigger must be composable) |
| B10 | Final Shim deletion | B8 + B9 + zero direct callers |

B2 and B3 each depend on B1 (interfaces must be visible first). B4-B6 depend on B2+B3. B7 depends on B4-B6. B10 is terminal. B8 and B9 are independently implementable but scheduled B8 first.

---

## 9. Service Locator Cleanup — Moved to B9/B10

These are now addressed in Phase B9/B10 (was originally planned for Phase C):
- `OcrFactory.Paddle` static → injected interface (B9)
- `PickTextInference` constructor → injected interface (B9)
- `Global.ReadAllTextIfExist` → file abstraction (B9)
- `ThemedMessageBox` → UI abstraction (B9)
- Shim deletion gated on zero callers (B10)


---

## B1 Status: Complete

Commit: `8622598`
Three interfaces relocated to shared upstream source tree.

---

## B2 Status: Complete

Commit: `2dde64a`. Windows providers + DI registration.

## B3 Status: Complete

Commit: `b05cba5`. Mac adapters + verification (20/20).

## B4 Status: Complete

Commit: 5c0bf82 OcrFactory takes IOcrRuntimeConfigProvider; zero TaskContext refs; fallback preserved.

## B4.1 Status: Complete

Commit: `17814cd`. Fallback logs, precise assertions, null check.

## B5 Status: Complete

Commit: bac0af9 AutoPickTrigger injects IAutoPickRuntimeState; Pen guards for macOS.

## B5.1 Status: Complete

Commit: `daf0c5c`. Unified master ctor, precise tests, restore System.Drawing 10.0.7.

## B5.2 Status: Complete

Commit: `4a36609`. Removed null-ambiguous overload; `new AutoPickTrigger(null)` compiles.

---

## B6 Status: Complete

**B6 implementation series:** `9bb2670` → `3554e60` → `41c555c` → `29a916f` → `13637e6`  
**B6 lifecycle stabilization:** `28fad4f` → `87ee973` → `b913e68` → `2aa199b` → `40a548f`
AutoPickAssets constructor split + Configure(IAutoPickConfigProvider):
- Template-only ctor; config-dependent logic deferred to Configure()
- Instance-level property guards (EnsureThisConfigured)
- DestroyInstance lifecycle + Configure re-entry guard
- Write-back semantics (PickKey = "F" on fallback)
- TaskTriggerDispatcher lifecycle (_started/_starting/_startFailed + CleanupFailedStart)

---

## B7 Status: Complete

**Design v2:** `44d95a3` — composition root in Core/Composition/, state machine, narrow deps, no IDisposable  
**Implementation:** `261c9eb` — MacAutoPickComposition.cs, AutoPickTrigger configProvider injection, lock sync  
**Verification fix:** `0cf37a7` — real Failed state test, redundant DestroyInstance removal, ConcurrentQueue  
**Verification:** 76 passed, 0 failed

### What B7 achieves

| Boundary | Status | Notes |
|----------|--------|-------|
| MacAutoPickComposition in Core/Composition/ | ✅ | Not in Adapters |
| Four-state machine + lock | ✅ | NotComposed/Composing/Composed/Failed |
| Null validation before state change | ✅ | ArgumentNullException, no Failed poison |
| AutoPickTrigger IAutoPickConfigProvider injection | ✅ | Master ctor: `(config, state, provider)` |
| Init config lookup avoids TaskContext when non-null provider injected | ✅ | `_configProvider?.AutoPickConfig ?? TaskContext...` |
| Compose failure → Failed → "Restart" | ✅ | Original exception preserved |
| One-shot per process | ✅ | All states guarded; no public reset |
| internal ResetForVerification | ✅ | Reflection access from tests |
| Concurrent safety | ✅ | lock + Barrier test (exactly 1 success) |
| Production code unchanged for Windows | ✅ | Two-param ctor delegates null |

### What B7 does NOT cover (B8+ scope)

| Gap | Code Location | Why Deferred |
|-----|---------------|-------------|
| OnCapture() TaskContext reads | lines 214-215 (AssetScale + AutoPickConfig offsets) | Needs ISystemInfoProvider + broader migration |
| Simulation.SendInput (Win32) | lines 198, 210, 257, 355, 386 | IInputBackend exists but OnCapture not migrated |
| OcrFactory.Paddle static | lines 310, 331 | Static gateway — needs DI (Phase C) |
| TextInferenceFactory static | line 297 | Same as OcrFactory (Phase C) |
| Shim deletion (17 files) | Core/Shim/*.cs | Gated on zero direct callers |
| File I/O abstraction | Global.ReadAllTextIfExist | Shim — needs IFileSystem (Phase C) |
| ThemedMessageBox | Shim — needs IUserInteractionService | Phase C |
