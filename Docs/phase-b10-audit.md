# B10 Audit: Shim Inventory and Classification

**Status:** Audit only — no code deleted
**Predecessor:** B9 complete (commit `f381378`, Core Verification 106/106)

---

## 1. Overview

20 files in `BetterGenshinImpact.Core/Shim/`, all compiled into the Core assembly:

```
App.cs  BgiKeyMapper.cs  BgiOnnxFactory.cs  BgiOnnxModel.cs
BvStubs.cs  ConfigService.cs  CoreExtensions.cs  DrawableStubs.cs
GameTaskManager.cs  GameUiCategory.cs  Global.cs  MacSystemInfo.cs
PlatformServices.cs  RunnerContext.cs  Simulation.cs  SpeedTimer.cs
StringUtils.cs  TaskContext.cs  TaskControl.cs  ThemedMessageBox.cs
```

---

## 2. Classification

### A. Directly deletable (zero references, no alternative needed)

| File | Reason |
|------|--------|
| `BvStubs.cs` | Unreferenced in linked upstream files; no callers in Core |
| `CoreExtensions.cs` | Unreferenced |
| `DrawableStubs.cs` | Unreferenced in AutoPick/composition chain |
| `GameUiCategory.cs` | Unreferenced |
| `StringUtils.cs` | Unreferenced |
| `TaskControl.cs` | Unreferenced |

These can be deleted in a single commit — no build or test impact.

### B. Should be replaced with linked shared source

| File | Upstream equivalent | Blockers to linking |
|------|---------------------|---------------------|
| `BgiKeyMapper.cs` | `Helpers/BgiKeyMapper.cs` | None — pure mapping, no WPF/Win32 dependency |
| `ConfigService.cs` | `Service/ConfigService.cs` | Upstream has WPF dependencies; shim is a thin stub |
| `Simulation.cs` | `Core/Simulator/Simulation.cs` | SendInputFacade may still have callers; need to verify |

### C. Must remain as compatibility shim (upstream has Windows-only dependencies)

| File | Upstream equivalent | Why it cannot be directly linked |
|------|---------------------|----------------------------------|
| `App.cs` | Root `App` (WPF) | Provides `GetLogger<T>()` and `ServiceProvider`; upstream is WPF Application |
| `BgiOnnxFactory.cs` | `ONNX/BgiOnnxFactory.cs` | Depends on `App.ServiceProvider` |
| `BgiOnnxModel.cs` | `ONNX/BgiOnnxModel.cs` | Used by BgiOnnxFactory |
| `Global.cs` | `Helpers/Global.cs` | Upstream has `Absolute()` etc; shim provides `ReadAllTextIfExist` |
| `MacSystemInfo.cs` | `Model/SystemInfo.cs` (Windows) | Mac-specific ISystemInfo implementation — no upstream equivalent |
| `PlatformServices.cs` | None | Static gateway for IInputBackend/DesktopRegion |
| `RunnerContext.cs` | `GameTask/RunnerContext.cs` | Full upstream has coordination methods; shim provides `AutoPickTriggerStopCount` field |
| `SpeedTimer.cs` | `Helpers/SpeedTimer.cs` | Used by AutoPickTrigger.OnCapture for debug perf recording |
| `TaskContext.cs` | `GameTask/TaskContext.cs` | Core/macOS Shim providing `Config` + `SystemInfo` |
| `ThemedMessageBox.cs` | `View/ThemedMessageBox.cs` (WPF) | UI dialog — cross-platform Core needs stub |

### D. Test fakes — should move to Test project

| File | Test use |
|------|----------|
| `PlatformServices.cs` | Verification sets `PlatformServices.Input = recorder` |
| `MacSystemInfo.cs` | Verification uses `new MacSystemInfo()` via Shim/TaskContext |

These are currently in the production Core assembly but only used by Verification.

---

## 3. GameTaskManager Deep Dive

### 3.1 Shim vs Upstream

| Aspect | Windows upstream (`BetterGenshinImpact/GameTask/GameTaskManager.cs`) | Core shim (`Shim/GameTaskManager.cs`) |
|--------|----------------------------------------------------------------------|----------------------------------------|
| Trigger types | All 12 task types | AutoPick only |
| `AddTrigger` | Full switch (AutoPick, AutoSkip, AutoEat) | AutoPick only |
| `LoadInitialTriggers` | Full lifecycle (ReloadAssets + Initialize + all triggers) | **Not present** in shim — only used via Windows GameTaskManager linked in core |
| `ConvertToTriggerList` | Full + Init + Priority sort | Simple filter |
| `ReloadAssets` | Destroys all asset singletons | **Not present** |
| `LoadAssetImage` | Resolution-aware + fallback + resize | Same (B8.2 added) |

### 3.2 Who calls what

| Caller | Target method | Which GameTaskManager? |
|--------|---------------|------------------------|
| `TaskTriggerDispatcher.Start()` | `LoadInitialTriggers` | **Windows upstream** (linked from `BetterGenshinImpact/GameTask/`) |
| `TaskRunner` | `ReloadInitialTriggers` → dispatcher → **Windows upstream** | — |
| `Verification B8.2 test` | `AddTrigger` | **Core shim** |
| `AutoPickAssets.InitTemplateAssets` | `LoadAssetImage` | **Core shim** (via linked compile) |

### 3.3 Can shim AddTrigger be eliminated?

The core shim `AddTrigger` is the only shim method used by Verification tests. The production macOS `MacAutoPickComposition` does NOT use `GameTaskManager.AddTrigger` — it creates `AutoPickTrigger` directly via the constructor.

**Recommendation:** Keep the shim `GameTaskManager` for asset loading (`LoadAssetImage`) and verification test access. `AddTrigger` can stay as a narrow verification-friendly entry point. No change needed.

---

## 4. Dependency Graph (AutoPick-related)

```
MacAutoPickComposition.Compose
  ├── AutoPickTrigger (required: configProvider, inputBackend, systemInfo, paddle, yap)
  │     ├── App.GetLogger            → Shim/App.cs (C)
  │     ├── Global.ReadAllTextIfExist → Shim/Global.cs (C)
  │     ├── ConfigService.JsonOptions → Shim/ConfigService.cs (C, but can be removed — see §5)
  │     ├── ThemedMessageBox.Error   → Shim/ThemedMessageBox.cs (C)
  │     ├── SpeedTimer               → Shim/SpeedTimer.cs (C)
  │     └── RunnerContext.Instance   → Shim/RunnerContext.cs (C — StopCount fallback)
  ├── AutoPickAssets.Initialize
  │     └── App.GetLogger            → Shim/App.cs (C)
  ├── AutoPickAssets.Instance
  │     └── GameTaskManager.LoadAssetImage → Shim/GameTaskManager.cs (C)
  └── TaskContext.Instance (via shim)
        └── Shim/TaskContext.cs (C — still provides SystemInfo for macOS shim path)
```

Key: (C) = Compatibility shim — must remain until upstream dependency removed.

---

## 5. Priority for B10.1 (first deletable batch)

**5 files** can be deleted immediately with zero impact:

| File | Lines | Notes |
|------|-------|-------|
| `BvStubs.cs` | ~10 | No references in any linked file |
| `CoreExtensions.cs` | ~10 | No references |
| `DrawableStubs.cs` | ~20 | No references (drawing methods guarded with `#if BGI_FULL_WINDOWS`) |
| `GameUiCategory.cs` | ~10 | Enum not referenced |
| `StringUtils.cs` | ~10 | Not referenced from AutoPick |
| `TaskControl.cs` | ~10 | Not referenced from AutoPick |

These can go in one commit. **Core Verification must remain 106/106.**

---

## 6. Planned Deletion Order

| Batch | Scope | Files | Verification |
|-------|-------|-------|-------------|
| B10.1 | Pure dead shim | BvStubs, CoreExtensions, DrawableStubs, GameUiCategory, StringUtils, TaskControl | Core Verification 106/106 |
| B10.2 | `BgiKeyMapper` → link upstream | Shim/BgiKeyMapper.cs → upstream `Helpers/BgiKeyMapper.cs` | Same |
| B10.3 | `ConfigService` → inline the single consumer | `ConfigService.JsonOptions` in AutoPickTrigger line 129 can be replaced with simple `JsonSerializerOptions` | Same |
| B10.4 | Evaluate remaining 8 compatibility shims | App, BgiOnnxFactory, BgiOnnxModel, Global, PlatformServices, RunnerContext, SpeedTimer, ThemedMessageBox | Each requires upstream dependency removal first |

---

## 7. Verification Baseline (for B10.1 impact check)

| Metric | Current |
|--------|---------|
| Core Verification | 106/106 |
| AutoPickTrigger static OCR refs | Zero (B9) |
| AutoPickTrigger TaskContext/Config refs | Zero (Init + OnCapture) |
| AutoPickTrigger remaining shims | App, Global, ConfigService, ThemedMessageBox, RunnerContext (StopCount), SpeedTimer |
| Core build errors | Zero |
| WPF B9 type resolution | Zero B9 errors |

---

## 8. Out of Scope

| NOT in B10 | Reason |
|------------|--------|
| Delete App, Global, ConfigService, ThemedMessageBox, RunnerContext, SpeedTimer, TaskContext | Still have linked callers; require upstream dependency changes |
| Merge GameTaskManager shim with upstream | Divergent responsibilities — shim is deliberately narrow |
| Implement real macOS OCR | Future |
| Full WPF build | Pre-existing backlog |
| Change AutoPick behavior | B10 is structural cleanup only |
