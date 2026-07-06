# B10 Audit: Shim Inventory and Classification (Revised)

**Status:** Audit only — trial deletion attempted, no shim proven deletable
**Predecessor:** B9 complete (commit `f381378`, Core Verification 106/106)

---

## 1. Core Assembly Boundary

`BetterGenshinImpact.Core` compiles the following (per `Core.csproj`, `EnableDefaultCompileItems=false`):

| Layer | Count | Source |
|-------|-------|--------|
| Linked upstream files | ~60 | `BetterGenshinImpact/` via `<Compile Include=... Link=...>` |
| Shim files | **20** | `Shim/*.cs` via `<Compile Include="Shim/...">` |
| Adapters | 4 | `Adapters/` (MacCoreRuntime, MacAutoPick, 2 Unsupported) |
| Composition | 1 | `Composition/MacAutoPickComposition.cs` |

**NOT compiled into Core:**
- `BetterGenshinImpact/GameTask/GameTaskManager.cs` (Windows upstream)
- `BetterGenshinImpact/GameTask/TaskTriggerDispatcher.cs` (Windows)
- `BetterGenshinImpact/Core/Runtime/Windows/` (Windows DI, adapters, backend)
- `BetterGenshinImpact/App.xaml.cs` (DI)

---

## 2. B10.1 Trial Deletion — Corrected Findings

### 2.1 Verification methodology

Source guard searches included all linked upstream files compiled via `BetterGenshinImpact.Core.csproj`, not just AutoPick:
- `BetterGenshinImpact/GameTask/AutoPick/`
- `BetterGenshinImpact/Core/Recognition/`
- `BetterGenshinImpact/GameTask/Model/Area/`
- `BetterGenshinImpact/GameTask/CaptureContent.cs`, `ITaskTrigger.cs`, `ISoloTask.cs`
- `BetterGenshinImpact/Core/Config/`, `Helpers/`, `Model/`

### 2.2 Six candidate re-evaluation

| File | Symbol(s) | Consumer(s) in linked sources | Deletable? |
|------|-----------|-------------------------------|-----------|
| `BvStubs.cs` | `Bv.ImRead()` | `PaddleOcrService.cs` — Core-linked, calls Bv.ImRead in pre-heat | **No** |
| `CoreExtensions.cs` | `ClampTo()`, `ToScalar()` | `ImageRegion.cs` [ClampTo], `RecognitionObject.cs` [ToScalar] | **No** — extension methods used by 2 linked files |
| `DrawableStubs.cs` | `DrawContent`, `VisionContext` | `Region.cs` [DrawContent ctor/PutRect/PutLine], `ImageRegion.cs` [RemoveRect, VisionContext] | **No** — drawing types used by 3 linked files |
| `GameUiCategory.cs` | `GameUiCategory` enum | `ITaskTrigger.cs` [SupportedGameUiCategory prop], `CaptureContent.cs` [field type] | **No** — enum used by 2 linked files |
| `StringUtils.cs` | `RemoveAllSpace()` | `ImageRegion.cs` [RemoveAllSpace call] | **No** — extension used by 1 linked file |
| `TaskControl.cs` | `Logger`, `CaptureToRectArea()`, `Sleep()` | `Region.cs` [Logger], `ImageRegion.cs` [Logger, CaptureToRectArea] | **No** — used by 2 linked files |

**Conclusion:** None of the 6 candidates could be deleted. The initial audit's "zero references" claim was incorrect because it only searched AutoPick, not the full ~60-file compilation closure.

### 2.3 Implication for remaining 14 shims

This result does **not** prove that all 20 shims are essential. The remaining 14 shims (`App`, `BgiKeyMapper`, `BgiOnnxFactory`, `BgiOnnxModel`, `ConfigService`, `GameTaskManager`, `Global`, `MacSystemInfo`, `PlatformServices`, `RunnerContext`, `Simulation`, `SpeedTimer`, `TaskContext`, `ThemedMessageBox`) have **not** been trial-deleted or fully audited for deletability.

B10 is not closed. Each remaining shim requires individual dependency evidence before a deletion attempt.

---

## 3. Current Shim Inventory and Known Consumers

| Shim | Known consumers | Evidence status |
|------|----------------|-----------------|
| `App.cs` | Logger, ServiceProvider | Known direct consumer |
| `BgiKeyMapper.cs` | AutoPickAssets | Known direct consumer |
| `BgiOnnxFactory.cs` | ONNX | Known direct consumer |
| `BgiOnnxModel.cs` | ONNX | Known direct consumer |
| `BvStubs.cs` | Bv.ImRead (PaddleOcrService — Core-linked) | **Verified required** (B10.1) |
| `ConfigService.cs` | AutoPickTrigger (JsonOptions) | Known direct consumer |
| `CoreExtensions.cs` | ImageRegion (ClampTo), RecognitionObject (ToScalar) | **Verified required** (B10.1) |
| `DrawableStubs.cs` | Region, ImageRegion (DrawContent, VisionContext) | **Verified required** (B10.1) |
| `GameTaskManager.cs` | AutoPickAssets (LoadAssetImage), Verification | Known direct consumer |
| `GameUiCategory.cs` | ITaskTrigger, CaptureContent (enum) | **Verified required** (B10.1) |
| `Global.cs` | AutoPickTrigger (ReadAllTextIfExist) | Known direct consumer |
| `MacSystemInfo.cs` | TaskContext shim (default SystemInfo) | Known direct consumer |
| `PlatformServices.cs` | DesktopRegion (5 calls), Simulation, Verification | Known direct consumer |
| `RunnerContext.cs` | AutoPickTrigger (StopCount fallback) | Known direct consumer |
| `Simulation.cs` | SendInputFacade | Known direct consumer |
| `SpeedTimer.cs` | AutoPickTrigger (debug perf) | Known direct consumer |
| `StringUtils.cs` | ImageRegion (RemoveAllSpace) | **Verified required** (B10.1) |
| `TaskContext.cs` | BaseAssets, OcrFactory, AutoPickAssets | Known direct consumer |
| `TaskControl.cs` | Region, ImageRegion (Logger, CaptureToRectArea) | **Verified required** (B10.1) |
| `ThemedMessageBox.cs` | AutoPickTrigger (error dialogs) | Known direct consumer |

**Key to Evidence status:**
- **Verified required (B10.1):** Trial deletion failed; direct symbol reference confirmed in Core-linked consumer
- **Known direct consumer:** Known caller exists but no trial deletion has been attempted
- Not yet audited means the file is assumed required until proven otherwise

**What "deletion" would require:** For any shim to be removable, ALL the linked upstream files compiled in Core must stop depending on its types/namespace. This typically requires either:
- Upstream code modification (replacing static calls with injected dependencies)
- Additional `#if BGI_FULL_WINDOWS` guards
- Wrapping in the Windows-only WPF project

Those changes are beyond B10 scope (they belong to the AutoPick/OCR extraction phase or a dedicated cleanup phase).

---

## 4. Verification Baseline

| Metric | Current |
|--------|---------|
| Core Verification | **106/106** ✅ |
| Core build errors | Zero ✅ |
| Shim files compiled | 20 |
| adapter-gate | Not triggered (no adapter changes) |
| Full WPF build | Pre-existing backlog (IAutoPickConfigProvider missing usings) |

---

## 5. B10.2 Audit: BgiKeyMapper

### 5.1 Current state

| Aspect | Detail |
|--------|--------|
| Shim file | `BetterGenshinImpact.Core/Shim/BgiKeyMapper.cs` |
| Upstream equivalent | **None** — the shim IS the authoritative source. No `Helpers/BgiKeyMapper.cs` exists in the WPF project tree. |
| Consumer(s) in Core-linked files | `AutoPickAssets.cs` line 174: `BgiKeyMapper.ToKey(keyName)` — single call site |
| Dependency chain | Pure C# → Platform.Abstractions (BgiKey enum) → no WPF/Win32/App.ServiceProvider → no transitive blockers |

### 5.2 Content comparison (shim is the only version)

- Namespace: `BetterGenshinImpact.Helpers` — same as the missing upstream target
- Method: `public static BgiKey ToKey(string key)` — single method, pure string → BgiKey mapping
- Dependencies: Only `BetterGenshinImpact.Platform.Abstractions` (BgiKey enum)
- No WPF/Win32/App.ServiceProvider/TaskContext references
- 36 lines total

### 5.3 Conclusion

**This shim can be replaced with linked shared source (Category B).**

Specifically:
1. Move `BetterGenshinImpact.Core/Shim/BgiKeyMapper.cs` → `BetterGenshinImpact/Helpers/BgiKeyMapper.cs` (WPF project tree)
2. WPF project auto-compiles it via default SDK glob
3. `BetterGenshinImpact.Core.csproj` replaces `<Compile Include="Shim/BgiKeyMapper.cs" />` with a linked reference:
   `<Compile Include="../BetterGenshinImpact/Helpers/BgiKeyMapper.cs" Link="Helpers/BgiKeyMapper.cs" />`
4. Delete `BetterGenshinImpact.Core/Shim/BgiKeyMapper.cs`

This eliminates one shim file, uses the existing shared-source pattern (same as `IAutoPickConfigProvider`, `ISystemInfo`, etc.), and has zero behavioral impact.

### 5.4 Risk

| Factor | Assessment |
|--------|-----------|
| Core build impact | None — same code, different compile item |
| Behavior change | None — single authoritative source |
| WPF build impact | None — now in WPF tree via default glob |
| Future divergence | None — single authoritative source |
| Adapter-gate | Not triggered (no adapter changes) |

### 5.5 B10.2 implementation result

| Metric | Before | After |
|--------|--------|-------|
| Shim file | `Shim/BgiKeyMapper.cs` | Deleted |
| Authoritative source | — | `BetterGenshinImpact/Helpers/BgiKeyMapper.cs` |
| Core compile item | `<Compile Include="Shim/BgiKeyMapper.cs" />` | `<Compile Include="../BetterGenshinImpact/Helpers/BgiKeyMapper.cs" Link="Helpers/BgiKeyMapper.cs" />` |
| WPF compile | — (not in WPF tree) | Default SDK glob |
| Shim count | 20 | **19** |
| Core Verification | 106/106 | 106/106 ✅ |
| WPF BgiKeyMapper type resolution | — | Zero errors ✅ |
| Source guard — only one definition | — | `BetterGenshinImpact/Helpers/BgiKeyMapper.cs` only ✅ |
| Source guard — old shim reference | — | Zero csproj hits ✅ |

---

## 6. B10.3 Audit: ConfigService

### 6.1 Current shim

| Aspect | Detail |
|--------|--------|
| File | `BetterGenshinImpact.Core/Shim/ConfigService.cs` |
| API | `public static readonly JsonSerializerOptions JsonOptions` |
| Options | `PropertyNameCaseInsensitive = true`, `WriteIndented = true` |
| Namespace | `BetterGenshinImpact.Service` |

### 6.2 Consumers in Core-linked files

| File | Line | Usage | Options required? |
|------|------|-------|-------------------|
| `AutoPickTrigger.cs` (linked) | 129 | `JsonSerializer.Deserialize<HashSet<string>>(json, ConfigService.JsonOptions)` | **No** — deserializing a JSON array of strings; `PropertyNameCaseInsensitive` and `WriteIndented` have zero effect on `HashSet<string>` deserialization |

**No other Core-linked file references `ConfigService` or its `JsonOptions`.**

### 6.3 Upstream comparison

| Aspect | WPF upstream (`Service/ConfigService.cs`) | Core shim |
|--------|-------------------------------------------|-----------|
| Type | Instance class `ConfigService : IConfigService` | Static class |
| `JsonOptions` settings | Same: `PropertyNameCaseInsensitive = true`, `WriteIndented = true` | Same |
| Additional API | Config file I/O, `AllConfig` management, `IConfigService` | None |
| WPF-only deps | File paths, DI, WPF types | None |

The shim's `JsonOptions` settings are identical to the upstream static field.

### 6.4 Conclusion

**Category E — removable after consumer decoupling.** The single consumer (`AutoPickTrigger.ReadJson`) stops depending on `ConfigService.JsonOptions`, then the shim is deleted. No linked shared-source migration needed; just a one-line change in the consumer.

**Approach:** Use the no-parameter overload:
```csharp
return JsonSerializer.Deserialize<HashSet<string>>(json) ?? [];
```
This is the clearest expression of "use default options" and avoids confusion about `null` semantics.

**Comparison proof:** For JSON arrays deserialized as `HashSet<string>`, the default overload and the legacy options produce equivalent sets. `PropertyNameCaseInsensitive` and `WriteIndented` have zero effect on string array deserialization.

### 6.5 Implementation plan

1. Change line 129: `ConfigService.JsonOptions` → call `JsonSerializer.Deserialize<HashSet<string>>(json)` (no-param overload)
2. Delete `BetterGenshinImpact.Core/Shim/ConfigService.cs`
3. Remove `<Compile Include="Shim/ConfigService.cs" />` from Core csproj
4. Add JSON equivalence test in Verification (see test gate below)
5. Verification: Core build zero errors, existing tests pass + JSON test passes
6. WPF type-resolution check: no new errors
7. Source guard: `rg 'ConfigService'` in Core compilation closure → zero hits
8. Shim count: 19 → 18

### 6.6 Implementation test gate

Add a test comparing deserialization with default options vs the original `ConfigService.JsonOptions`:

```csharp
var testJson = @"[""Apple"",""Mint"",""甜甜花"",""Apple""]";
var defaultResult = JsonSerializer.Deserialize<HashSet<string>>(testJson) ?? [];
var legacyOptions = new JsonSerializerOptions { PropertyNameCaseInsensitive = true, WriteIndented = true };
var legacyResult = JsonSerializer.Deserialize<HashSet<string>>(testJson, legacyOptions) ?? [];
Assert(defaultResult.SetEquals(legacyResult), "default options produce same set as legacy options");
Assert(defaultResult.Contains("Apple"), "Apple");
Assert(defaultResult.Contains("Mint"), "Mint");
Assert(defaultResult.Contains("甜甜花"), "甜甜花");
Assert(defaultResult.Count == 3, "duplicate Apple deduplicated");
```

Also test empty array:
```csharp
var empty = JsonSerializer.Deserialize<HashSet<string>>("[]") ?? [];
Assert(empty.Count == 0, "empty array → empty set");
```

### 6.7 Risk

| Factor | Assessment |
|--------|-----------|
| Behavior change | **None** — `PropertyNameCaseInsensitive` and `WriteIndented` have zero effect on `HashSet<string>` deserialization |
| Future proof | Could miss options if a non-string type is deserialized later; low risk, easy to add |
| Verification | Existing baseline 106/106; JSON equivalence test required during implementation |
| Source guard | Only one consumer site to change |

### 6.8 B10.3 Implementation Result

| Metric | Before | After |
|--------|--------|-------|
| ConfigService shim | `Shim/ConfigService.cs` | Deleted ✅ |
| AutoPickTrigger line 129 | `ConfigService.JsonOptions` | No-param `Deserialize<HashSet<string>>(json)` ✅ |
| Core csproj compile item | `<Compile Include="Shim/ConfigService.cs" />` | Deleted ✅ |
| Core Verification | 106/106 | **112/112** ✅ (+6 JSON assertions) |
| GameUiCategory.cs | Accidentally modified by B10.3 commit | Restored to original (corrective commit) ✅ |
| WPF ConfigService type resolution | — | Zero errors ✅ |
| Source guard: `ConfigService` in Core closure | — | Zero hits ✅ |
| Shim count | 19 | **18** ✅ |

---

## 7. B10.4 Audit: SpeedTimer

### 7.1 Current state

Two copies exist:

| Aspect | Upstream (`BetterGenshinImpact/Helpers/SpeedTimer.cs`) | Core shim (`BetterGenshinImpact.Core/Shim/SpeedTimer.cs`) |
|--------|--------------------------------------------------------|------------------------------------------------------------|
| Origin | Added in commit bf06ba3 ("fixed #3237") — original upstream | Added in commit 32590fc (macOS extraction) — simplified copy |
| Constructor | `SpeedTimer()` and `SpeedTimer(string name)` | `SpeedTimer()` only |
| Timer type | `Stopwatch`, stores `TimeSpan` in `_timeRecordDic` | `Stopwatch`, stores `long` ms in `_records` |
| `Record()` | Saves `_stopwatch.Elapsed`, then `_stopwatch.Restart()` | Saves `_stopwatch.ElapsedMilliseconds` (no restart) |
| `DebugPrint()` | **Real output:** formats and logs via `Debug.WriteLine()` | **No-op** — empty body |
| Dependencies | Pure C# (`Stopwatch`, `Debug`), no WPF/Win32 | Same |

### 7.2 Consumers

| Consumer file | Compiled in Core? | Calls `DebugPrint()`? | Would regress without real impl? |
|---------------|-------------------|-----------------------|----------------------------------|
| `AutoPickTrigger.cs` | ✅ Yes (1x) | ✅ Yes (line 371) | No — currently receives no-op; real output would be additive |
| `TaskTriggerDispatcher.cs` | ❌ WPF-only (1x) | ✅ Yes | Yes — currently receives real `Debug.WriteLine` output |
| `CombatScenes.cs` | ❌ WPF-only (1x) | ✅ Yes | Yes |
| `Feature2DExtensions.cs` | ❌ WPF-only (3x) | ✅ Yes | Yes |
| `BaseMapLayer.cs` | ❌ WPF-only (1x) | ✅ Yes | Yes |
| `BaseMapLayerByTemplateMatch.cs` | ❌ WPF-only (1x) | ✅ Yes | Yes |
| `SceneBaseMapByTemplateMatch.cs` | ❌ WPF-only (2x) | ✅ Yes | Yes |
| `BigMapMatchTest.cs` (Test) | ❌ (2x) | ✅ Yes | Yes |
| `EntireMapTest.cs` (Test) | ❌ (1x) | ✅ Yes | Yes |
| `FeatureMatcher.cs` (Test) | ❌ (4x) | ✅ Yes | Yes |

**Core-only consumer:** `AutoPickTrigger.OnCapture` — debug performance timing, no business impact.

### 7.3 Conclusion

**Category B — link upstream `BetterGenshinImpact/Helpers/SpeedTimer.cs` into Core, delete shim.**

The upstream file is pure C#, has no WPF/Win32 dependencies, and is already in the WPF project tree. Core should link it the same way it links other `Helpers/*.cs` files.

**This is NOT a case of "shim becomes authoritative source."** The authoritative source is the **upstream `Helpers/SpeedTimer.cs`**, which already exists and has real `DebugPrint` output. The shim is an inferior copy that should be replaced.

### 7.4 Implementation result

| Metric | Before | After |
|--------|--------|-------|
| Core SpeedTimer source | `Shim/SpeedTimer.cs` (inferior no-op copy) | Linked `Helpers/SpeedTimer.cs` (upstream) ✅ |
| Core csproj shim item | `<Compile Include="Shim/SpeedTimer.cs" />` | Deleted ✅ |
| Core csproj linked item | — | `<Compile Include="../BetterGenshinImpact/Helpers/SpeedTimer.cs" Link="Helpers/SpeedTimer.cs" />` ✅ |
| Core production behavior | Unchanged | Unchanged ✅ |
| Core diagnostic behavior | Cumulative ms + no-op | Per-stage TimeSpan + Debug.WriteLine ✅ |
| WPF diagnostic behavior | Real output | Unchanged (same upstream file) ✅ |
| Core Verification | 112/112 | 112/112 ✅ |
| Source guard: SpeedTimer definitions | — | **1** (`BetterGenshinImpact/Helpers/SpeedTimer.cs`) ✅ |
| Source guard: shim reference | — | Zero csproj hits ✅ |
| WPF SpeedTimer type resolution | — | Zero errors ✅ |
| Shim count | 18 | **17** ✅ |

### 7.5 Behavior impact

| Layer | Impact |
|-------|--------|
| Core production behavior | **Unchanged** — no timing value is consumed by decision/state logic |
| Core diagnostic behavior | **Changed to match upstream:** Record() becomes per-stage timing via Stopwatch.Restart(); stored value changes from cumulative `long` ms to `TimeSpan`; DebugPrint() restores `Debug.WriteLine` output; DebugPrint() stops the stopwatch |
| WPF diagnostic behavior | **Unchanged** — uses the same upstream file as before |
| AutoPickTrigger semantics | Uses sequential `Record()` calls across named pipeline stages. Upstream restart-after-record behavior is the **intended per-stage timing semantics**; the shim's cumulative timing and no-op output were drift from upstream behavior |

---

## 8. B10.5 Audit: TaskContext

### 8.1 Current shim

| Aspect | Detail |
|--------|--------|
| File | `BetterGenshinImpact.Core/Shim/TaskContext.cs` |
| Namespace | `BetterGenshinImpact.GameTask` |
| Type | Instance class with double-checked-locking singleton |
| Properties | `IsInitialized` (bool), `SystemInfo` (ISystemInfo, defaults to `new MacSystemInfo()`), `Config` (CoreConfig, defaults to `new()`) |
| Methods | `Instance()` (static singleton), `Init(GameWindowMetrics)` (sets MacSystemInfo), `DestroyInstance()` |
| `CoreConfig` | Contains `AutoPickConfig` + `OtherConfig` — minimal subset of upstream `AllConfig` |
| Comment | "Thin facade: provides TaskContext.Instance() for cross-platform Core. Windows-specific fields excluded." |

### 8.2 Upstream comparison

| Member | Upstream (`GameTask/TaskContext.cs`) | Core shim | In preprocessed Core compilation? |
|--------|--------------------------------------|-----------|-----------------------------------|
| `Instance()` | `LazyInitializer.EnsureInitialized` | Double-checked lock | ✅ Yes (only static entry point) |
| `IsInitialized` | `bool` | Same | Not in current Core closure |
| `SystemInfo` | `ISystemInfo` — set via `Init(hWnd)` | `ISystemInfo` — defaults to new MacSystemInfo() | ✅ Yes (BaseAssets default ctor) |
| `Config` | `AllConfig` — reads ConfigService | `CoreConfig` — minimal container | ❌ Only ref is `#if BGI_FULL_WINDOWS` (AutoPickAssets line 176) |
| `DpiScale` | `float` — Win32 DPI | **Absent** | ❌ Only refs are inside `#if BGI_FULL_WINDOWS` (GameCaptureRegion) |
| `GameHandle` | `IntPtr` — Win32 HWND | **Absent** | ❌ WPF-only |
| `PostMessageSimulator` | Win32 PostMessage wrapper | **Absent** | ❌ Line 99 inside `#if BGI_FULL_WINDOWS` (Region.cs) |
| `LinkedStartGenshinTime` | `DateTime` | **Absent** | ❌ WPF-only |
| `CurrentScriptProject` | Script grouping | **Absent** | ❌ WPF-only |
| `GetGenshinGameProcessNameList()` | Process name resolution | **Absent** | ❌ WPF-only |

**Key correction from earlier audit:** Members absent from the Core shim (`DpiScale`, `PostMessageSimulator`) do NOT cause null references or NREs in Core because all call sites in linked files are guarded by `#if BGI_FULL_WINDOWS`, which is not defined in the Core project (`BGI_PLATFORM_MAC` is defined instead).

### 8.3 Preprocessed Core references

| File | Line | Code | Preprocessed in Core? |
|------|------|------|-----------------------|
| `BaseAssets.cs` | 21 | `TaskContext.Instance().SystemInfo` (default ctor) | ✅ **Compiled reference** |
| `AutoPickAssets.cs` | 176 | `TaskContext.Instance().Config.KeyBindingsConfig...` | ❌ Inside `#if BGI_FULL_WINDOWS` |
| `GameCaptureRegion.cs` | 29,46,94–111 | `TaskContext.Instance().DpiScale` / `.SystemInfo.*` | ❌ Inside `#if BGI_FULL_WINDOWS` |
| `Region.cs` | 99 | `TaskContext.Instance().PostMessageSimulator` | ❌ Inside `#if BGI_FULL_WINDOWS` |
| Verification `Program.cs` | 179,181,396 | `TaskContext.Instance()` | ✅ **Test reference** |

**The only remaining preprocessed Core production reference is `BaseAssets<T>`'s parameterless constructor** calling `TaskContext.Instance().SystemInfo`. Whether that constructor is reachable from a supported Core runtime path must be audited separately.

### 8.4 Reachability analysis

#### AutoPickAssets — does NOT use the parameterless ctor from the supported path

```
MacAutoPickComposition.Compose(systemInfo, configProvider, ...)
  → AutoPickAssets.Initialize(systemInfo, configProvider)
    → private AutoPickAssets(ISystemInfo systemInfo) : base(systemInfo)
      → BaseAssets(systemInfo)                         ← no TaskContext
    → (configProvider applied via Configure())
    → _instance = instance
  → AutoPickAssets.Instance
    → hidden new static property — throws if not initialized
```

The parameterless constructor (`private AutoPickAssets() : base()` → `TaskContext.Instance().SystemInfo`) exists only for legacy source compatibility. The supported composition path does NOT reach it.

#### Which BaseAssets-derived types are linked in Core?

Per Core csproj, the only linked `BaseAssets<T>` concrete production type is **AutoPickAssets**. Other types (AutoSkipAssets, AutoFightAssets, etc.) are NOT compiled into Core.

#### Singleton<T> behavior

`Singleton<T>` uses `Activator.CreateInstance(typeof(T), true)` which invokes the private parameterless constructor. However, AutoPickAssets' `new static Instance` property **hides** the inherited `Singleton<T>.Instance` member — it throws before reaching `Singleton<T>.Instance`, and `Initialize()` directly writes `_instance`, bypassing `Activator`. The inherited `Singleton<AutoPickAssets>.Instance` remains technically callable through the base generic type or reflection, but no supported Core composition path uses it.

#### Conclusion

The `BaseAssets<T>` parameterless constructor compiles a reference to `TaskContext.Instance().SystemInfo`, but it is **not reachable from any supported AutoPick Core runtime composition path**. Existence of the reference is a legacy compliance burden, not an active production dependency.

### 8.5 Dependency graph

```
── Compiled reference graph ──────────────────────────────
BaseAssets<T>.BaseAssets()     (parameterless legacy ctor)
  → TaskContext.Instance()
    → ISystemInfo
  ↳ NOT reachable from supported AutoPick Core runtime

── Supported AutoPick Core runtime graph ─────────────────
MacAutoPickComposition.Compose(systemInfo, configProvider, ...)
  → AutoPickAssets.Initialize(systemInfo, configProvider)
    → private AutoPickAssets(systemInfo) : base(systemInfo)
      → BaseAssets(systemInfo)     ✅ no TaskContext
    → Configure(configProvider)
    → _instance = instance
  → AutoPickAssets.Instance → returns _instance

── Verification graph ────────────────────────────────────
Program.cs
  → TaskContext.Instance()     (test infrastructure only)
    → SystemInfo = new MacSystemInfo()
    → Config.CoreConfig
```

### 8.6 Architecture classification

**TaskContext is a service locator / context bag.** The Core shim retains the static `Instance()` singleton pattern and `CoreConfig`. However, the only reachable production path (AutoPickAssets via Initialize) already bypasses it. The shim survives only because `BaseAssets<T>`'s legacy parameterless constructor still textually references it.

### 8.7 Recommendation

**Category C/D hybrid — keep shim temporarily; deletion may require only removing an unreachable legacy constructor.**

Do NOT assume broad constructor injection work is necessary. The reachability audit determines the scope.

### 8.8 Minimal phase plan (not implemented in B10.5)

| Phase | Scope | Gate |
|-------|-------|------|
| B10.5.1 | Reachability audit: confirm no supported Core composition path invokes `BaseAssets()` parameterless ctor for any linked type | Documented audit |
| B10.5.2 | If unreachable: remove or compile-exclude only the legacy `BaseAssets()` default ctor's TaskContext reference (e.g. add `#if` guard or delete unreachable code) | Core builds, 112/112 |
| B10.5.3 | Remove Verification dependence on TaskContext/CoreConfig if any | Same |
| B10.5.4 | Delete TaskContext shim + CoreConfig after preprocessed references reach zero | rg TaskContext zero in Core closure |

If a reachable consumer is found, design required constructor injection for that specific consumer — not a wholesale refactor.

### 8.9 B10.5.2 Implementation Result

| Change | File | Detail |
|--------|------|--------|
| BaseAssets parameterless ctor | `BaseAssets.cs` | Entire ctor wrapped in `#if BGI_FULL_WINDOWS` — absent from Core compilation; Core now enforces ISystemInfo injection at compile time for BaseAssets-derived types |
| AutoPickAssets legacy ctor | `AutoPickAssets.cs` | Guarded with `#if BGI_FULL_WINDOWS` — not compiled in Core |
| Core Verification | — | 112/112 ✅ |
| WPF behavior | — | Unchanged — both parameterless ctors still compiled under `BGI_FULL_WINDOWS` ✅ |
| TaskContext shim | — | Retained (Verification still uses it) |
| Shim count | — | 17 (unchanged) |

### 8.10 B10.5.3 Implementation Result

| Change | Detail |
|--------|--------|
| Verification `TaskContext.Instance()` | Removed — replaced with direct `new MacSystemInfo()` |
| Verification `TaskContext.Config` mutation | Removed — test now verifies provider wins without manipulating TaskContext |
| Core Verification | 112/112 ✅ |
| Source guard: `TaskContext.Instance()` in Verification | Zero code refs ✅ (one comment remains) |
| TaskContext shim | Retained — ready for B10.5.4 deletion evaluation |

### 8.11 Baseline

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 112/112
```

### 8.12 B10.5.4 Implementation Result

| Change | Detail |
|--------|--------|
| Core TaskContext shim | `Shim/TaskContext.cs` — deleted ✅ |
| CoreConfig | Deleted with shim (defined in same file) ✅ |
| Core csproj entry | `<Compile Include="Shim/TaskContext.cs" />` — removed ✅ |
| CaptureContent(Mat, frameIndex, interval) | Entire constructor compiled only under `#if BGI_FULL_WINDOWS`; Core retains only `CaptureContent(ImageRegion)`, preserving non-null `CaptureRectArea` contract |
| Core production references | Zero (comments only) ✅ |
| Verification references | Zero (one comment) ✅ |
| WPF | Continues using upstream `GameTask/TaskContext.cs` ✅ |
| Upstream link added? | **No** — upstream is WPF-host-only; not suitable for Core |
| Core Verification | 112/112 ✅ |
| Shim count | 17 → **16** ✅ |

---

## 9. B10.6 Audit: RunnerContext

### 9.1 Current shim

| Aspect | Detail |
|--------|--------|
| File | `BetterGenshinImpact.Core/Shim/RunnerContext.cs` |
| Lines | 30 |
| Namespace | `BetterGenshinImpact.GameTask` |
| Type kind | `public class RunnerContext` — plain class, no base, no `Singleton<T>` |
| Instance access | Static singleton with double-checked locking: `private static RunnerContext? _instance` + `object _locker` |
| Public API | `public static RunnerContext Instance { get; }` (get-only) |
| Fields | `public volatile int AutoPickTriggerStopCount;` — mutable, volatile, no property wrapper |
| Constructor | Implicit parameterless |
| Comment | `"TEMPORARY VERIFICATION SHIM: provides RunnerContext.Instance.AutoPickTriggerStopCount. The real RunnerContext references AutoFight, AutoPathing, CombatScenes, TaskProgress etc. Long-term: split upstream RunnerContext into a Core-facing interface."` |
| Nullable enabled | Yes (file-scoped `#nullable` not set; project-level `Nullable=enable` applies) |

### 9.2 Upstream/history investigation

#### 9.2.1 Upstream WPF definition

| Aspect | Upstream (`BetterGenshinImpact/GameTask/RunnerContext.cs`) |
|--------|-----------------------------------------------------------|
| Lines | 217 |
| Type | `public class RunnerContext : Singleton<RunnerContext>` |
| Added | Commit `bf06ba3` ("fixed #3237", 2026-07-03) — original upstream commit |
| Modifications after creation | **None** — single creation commit, never modified |

Full upstream API surface:

| Member | Kind | Type / Signature | Notes |
|--------|------|------------------|-------|
| `Instance` | Static property (inherited) | `Singleton<RunnerContext>.Instance` | Via `LazyInitializer.EnsureInitialized` + `Activator.CreateInstance` |
| `IsContinuousRunGroup` | Auto-property | `bool` | Read/write |
| `taskProgress` | Auto-property | `TaskProgress?` | Read/write |
| `IsSuspend` | Auto-property | `bool` | Read/write |
| `IsPreExecution` | Auto-property | `bool` | Default `false` |
| `SuspendableDictionary` | Field (public) | `Dictionary<string, ISuspendable>` | Mutable, allocated in ctor |
| `isAutoFetchDispatch` | Auto-property | `bool` | Read/write |
| `PartyName` | Auto-property | `string?` | Nullable, read/write |
| `AutoPickTriggerStopCount` | Auto-property | `int` | Private set, default `0` |
| `_combatScenes` | Backing field | `CombatScenes?` | Private, mutable |
| `GetCombatScenes(CancellationToken)` | Async method | `Task<CombatScenes?>` | Lazy-init with capture call |
| `TrySyncCombatScenesSilent()` | Method | `CombatScenes?` | Silent capture + init |
| `ClearCombatScenes()` | Method | `void` | Sets `_combatScenes = null` |
| `Clear()` | Method | `void` | Resets task-scoped state |
| `Reset()` | Method | `void` | Resets all state to defaults |
| `StopAutoPick(int time = -1)` | Method | `void` | Inc stop count, schedule resume |
| `ResumeAutoPick(int time = 0)` | Method | `void` | Dec stop count (or schedule) |
| `StopAutoPickRunTask(Func<Task>, int)` | Method | `async Task` | Execute while paused |
| `stop()` | Method | `void` | Clear combat scenes only |

Upstream dependencies (C# type-level, beyond System):

| Dependency | Type | Purpose |
|------------|------|---------|
| `AutoFight.Model.CombatScenes` | WPF task type | Team/character recognition |
| `AutoPathing.Suspend.ISuspendable` | WPF task type | Suspend dictionary values |
| `Common.Job.ReturnMainUiTask` | WPF task type | Return-to-main-ui before team scan |
| `Common.TaskControl.*` | Static gateway | `CaptureToRectArea()`, `Delay()`, `Logger` |
| `Microsoft.Extensions.Logging.ILogger` | External | Logging |
| `Model.Singleton<T>` | WPF base | Singleton infrastructure |

#### 9.2.2 Shim origin

| Aspect | Value |
|--------|-------|
| Commit | `32590fc` ("macOS arm64 OpenCV native runtime + reproducible build script", 2026-07-04) |
| Operation | Created new file `BetterGenshinImpact.Core/Shim/RunnerContext.cs` |
| Author | Jac0b_Shi (macOS port author) |
| Nature | **Freshly written minimal shim** — not a copy of upstream, not a historical artifact |

The shim was written specifically to satisfy the `RunnerContext.Instance.AutoPickTriggerStopCount` type reference in the linked `AutoPickTrigger.cs`. It was never part of the upstream tree — it is a **compatibility-only compile shim**.

#### 9.2.3 Historical definitions

| Location | Exists? | Status |
|----------|---------|--------|
| Current Core shim | ✅ `BetterGenshinImpact.Core/Shim/RunnerContext.cs` | Active (30 lines) |
| Current upstream WPF | ✅ `BetterGenshinImpact/GameTask/RunnerContext.cs` | Active (217 lines) |
| Any other definition | ❌ | No -- only two files define `RunnerContext` type |
| Renamed/moved | ❌ | Never renamed or moved |
| Split from other type | ❌ | Original single-file type |

#### 9.2.4 Git log

```
bf06ba3 fixed #3237                                    A      GameTask/RunnerContext.cs
32590fc macOS arm64 OpenCV native runtime + build script A      Core/Shim/RunnerContext.cs
```

No modifications, renames, or moves in history. Both files created at their current location.

### 9.3 Preprocessed reference table

All textual references to `RunnerContext` across the repo, evaluated after Core preprocessing (`BGI_PLATFORM_MAC` defined, `BGI_FULL_WINDOWS` not defined):

#### 9.3.1 Core-compiled references (survive preprocessing)

| # | File | Project | Line | Code | Preprocessed? | Notes |
|---|------|---------|------|------|---------------|-------|
| 1 | `BetterGenshinImpact.Core/Shim/RunnerContext.cs` | Core | 1–30 | Type definition | ✅ Compiled | The shim itself |
| 2 | `BetterGenshinImpact/GameTask/AutoPick/AutoPickTrigger.cs` | Core (linked) | 63 | `/// fall back to RunnerContext for Windows legacy paths.` | ✅ Compiled | Comment only |
| 3 | `BetterGenshinImpact/GameTask/AutoPick/AutoPickTrigger.cs` | Core (linked) | 66 | `_runtimeState?.StopCount ?? RunnerContext.Instance.AutoPickTriggerStopCount;` | ✅ **Compiled reference** | Single production consumer |
| 4 | `BetterGenshinImpact.Core/Adapters/MacCoreRuntimeAdapter.cs` | Core | 9 | `/// no reference to TaskContext, RunnerContext, or Windows APIs.` | ✅ Compiled | Comment only |

**Total Core production references after preprocessing: 1 (one field access in AutoPickTrigger line 66).**

#### 9.3.2 WPF-only references (not compiled in Core)

| # | File | Lines | Count | Nature |
|---|------|-------|-------|--------|
| 1 | `BetterGenshinImpact/GameTask/TaskRunner.cs` | 71,79,89,107 | 4 | Instance lifecycle (Clear, IsContinuousRunGroup) |
| 2 | `BetterGenshinImpact/GameTask/Common/TaskControl.cs` | 55,56,60,74,89,90 | 6 | Pause/suspend orchestration |
| 3 | `BetterGenshinImpact/GameTask/Common/Job/SwitchPartyTask.cs` | 197 | 1 | Combat scenes invalidation |
| 4 | `BetterGenshinImpact/GameTask/SkillCd/SkillCdTrigger.cs` | 218 | 1 | Combat scenes silent init |
| 5 | `BetterGenshinImpact/GameTask/AutoPathing/PathExecutor.cs` | 135,138,256,267,403,430,431,459,649,675,687,688,699 | 13 | Suspend, PartyName, CombatScenes, Dispatch |
| 6 | `BetterGenshinImpact/GameTask/AutoPathing/Handler/MiningHandler.cs` | 50 | 1 | GetCombatScenes |
| 7 | `BetterGenshinImpact/GameTask/AutoPathing/Handler/PickUpCollectHandler.cs` | 54 | 1 | GetCombatScenes |
| 8 | `BetterGenshinImpact/GameTask/AutoPathing/Handler/LinneaMiningHandler.cs` | 22 | 1 | GetCombatScenes |
| 9 | `BetterGenshinImpact/GameTask/AutoPathing/Handler/NahidaCollectHandler.cs` | 23 | 1 | GetCombatScenes |
| 10 | `BetterGenshinImpact/GameTask/AutoPathing/Handler/AutoFightHandler.cs` | 61 | 1 | StopAutoPickRunTask |
| 11 | `BetterGenshinImpact/GameTask/AutoPathing/Handler/ElementalCollectHandler.cs` | 20 | 1 | GetCombatScenes |
| 12 | `BetterGenshinImpact/GameTask/AutoPathing/Handler/CombatScriptHandler.cs` | 21 | 1 | GetCombatScenes |
| 13 | `BetterGenshinImpact/GameTask/AutoLeyLineOutcrop/AutoLeyLineOutcropTask.cs` | 999,1666 | 2 | GetCombatScenes, PartyName |
| 14 | `BetterGenshinImpact/GameTask/AutoFight/AutoFightJsonTask.cs` | 690,692,758,777,778,779,896,897,898 | 9 | PartyName, CombatScenes |
| 15 | `BetterGenshinImpact/GameTask/AutoFight/AutoFightTask.cs` | 559,561,634,654,655,656,788,789,790 | 9 | PartyName, CombatScenes |
| 16 | `BetterGenshinImpact/Service/ScriptService.cs` | 154,171,187,189,247,254,266,268,308,320,367,385,434,439,527,541,547,553 | 18 | IsPreExecution, task orchestration |
| 17 | `BetterGenshinImpact/ViewModel/Pages/ScriptControlViewModel.cs` | 1988,1994,2432,2443,2485 | 5 | Reset, taskProgress, IsContinuousRunGroup |
| 18 | `BetterGenshinImpact/ViewModel/Pages/HotKeyPageViewModel.cs` | 378 | 1 | IsSuspend toggle |
| 19 | `BetterGenshinImpact/Core/Runtime/Windows/WindowsAutoPickRuntimeState.cs` | 7,12 | 2 | Adapter: delegates to RunnerContext.Instance |
| 20 | `BetterGenshinImpact/Core/Script/Dependence/Genshin.cs` | 301 | 1 | ClearCombatScenes |

**WPF-only total: ~88 textual references across 20 files, all using members absent from the Core shim.**

#### 9.3.3 Verification references

**Zero.** The Verification project has no textual references to `RunnerContext`.

### 9.4 Reachability analysis

#### 9.4.1 Compiled reference graph (after Core preprocessing)

```
Core compilation closure (BGI_PLATFORM_MAC)
│
├── Shim/RunnerContext.cs ───────── definition (self)
│
├── AutoPickTrigger.cs (linked) ── line 66:
│   _runtimeState?.StopCount ?? RunnerContext.Instance.AutoPickTriggerStopCount
│   │
│   └── Runtime resolution:
│       BGI_PLATFORM_MAC → resolves to Shim/RunnerContext.cs
│       In WPF (BGI_FULL_WINDOWS) → resolves to GameTask/RunnerContext.cs
│
└── MacCoreRuntimeAdapter.cs ───── line 9 comment only (no symbol resolution)
```

#### 9.4.2 Supported Core runtime graph (macOS)

```
MacAutoPickComposition.Compose(runtimeState, ...)
  → AutoPickTrigger(externalConfig, runtimeState, ...)
    → StopCount = _runtimeState.StopCount       ← null-conditional: _runtimeState is NEVER null
    → ?? RunnerContext.Instance...               ← DEAD BRANCH on macOS
```

**The `RunnerContext.Instance.AutoPickTriggerStopCount` fallback is unreachable on macOS** because `MacAutoPickComposition.Compose` always provides a non-null `IAutoPickRuntimeState` (`MacAutoPickRuntimeState`). The null-coalescing operator (`??`) only evaluates the right-hand side when the left-hand side (`_runtimeState?.StopCount`) is null, which never occurs in the supported composition path.

#### 9.4.3 Verification graph

```
Verification (Test/BetterGenshinImpact.Core.Verification)
  → No RunnerContext references (zero textual, zero compiled)
  → AutoPickTrigger tests use IAutoPickRuntimeState directly
```

#### 9.4.4 Windows-only graph (not compiled in Core)

```
TaskRunner.Run() ───→ RunnerContext.Instance.Clear()
                    → RunnerContext.Instance.IsContinuousRunGroup
ScriptService ──────→ RunnerContext.Instance.IsPreExecution (18 refs)
PathExecutor ───────→ RunnerContext.Instance.SuspendableDictionary, PartyName, GetCombatScenes
AutoFightTask ──────→ RunnerContext.Instance.PartyName, ClearCombatScenes, GetCombatScenes
TaskControl ────────→ RunnerContext.Instance.IsSuspend, StopAutoPick, SuspendableDictionary
SkillCdTrigger ─────→ RunnerContext.Instance.TrySyncCombatScenesSilent()
HotKeyViewModel ────→ RunnerContext.Instance.IsSuspend toggle
ScriptControlVM ────→ RunnerContext.Instance.Reset(), taskProgress
WindowsAutoPickRuntimeState → RunnerContext.Instance.AutoPickTriggerStopCount (adapter)
```

### 9.5 Semantic comparison: shim vs upstream

| Aspect | Upstream (`RunnerContext : Singleton<RunnerContext>`) | Core shim (`class RunnerContext`) | Delta |
|--------|------------------------------------------------------|------------------------------------|-------|
| Base type | `Singleton<RunnerContext>` | None (plain `class`) | Difference in instance creation |
| Instance init | `LazyInitializer.EnsureInitialized` + `Activator.CreateInstance` | Double-checked lock + `new RunnerContext()` | Similar semantics |
| `DestroyInstance()` | Inherited: `_instance = null` | **Absent** | Shim missing |
| `IsContinuousRunGroup` | `bool` auto-property | **Absent** | Shim missing |
| `taskProgress` | `TaskProgress?` auto-property | **Absent** | Shim missing |
| `IsSuspend` | `bool` auto-property | **Absent** | Shim missing |
| `IsPreExecution` | `bool` auto-property (default false) | **Absent** | Shim missing |
| `SuspendableDictionary` | `Dictionary<string, ISuspendable>` field | **Absent** | Shim missing |
| `isAutoFetchDispatch` | `bool` auto-property | **Absent** | Shim missing |
| `PartyName` | `string?` auto-property | **Absent** | Shim missing |
| `AutoPickTriggerStopCount` | `int` auto-property, private set | `public volatile int` field | Different visibility, different mutability control |
| `GetCombatScenes(CancellationToken)` | async method → `Task<CombatScenes?>` | **Absent** | Shim missing |
| `TrySyncCombatScenesSilent()` | method → `CombatScenes?` | **Absent** | Shim missing |
| `ClearCombatScenes()` | method | **Absent** | Shim missing |
| `Clear()` | method (partial reset) | **Absent** | Shim missing |
| `Reset()` | method (full reset to defaults) | **Absent** | Shim missing |
| `StopAutoPick(int)` | method | **Absent** | Shim missing |
| `ResumeAutoPick(int)` | method | **Absent** | Shim missing |
| `StopAutoPickRunTask(Func<Task>,int)` | async method | **Absent** | Shim missing |
| `stop()` | method | **Absent** | Shim missing |
| Thread-safety: concurrent access | `LazyInitializer`, no field-level synchronization | `volatile int` field | Partial — volatile only |
| Semantics on macOS | N/A (not compatible) | Compile shim only | Shim has no runtime effect |

**Critical semantic gaps in the shim:**

| Gap | Implication |
|-----|-------------|
| `AutoPickTriggerStopCount` is `public volatile int` field (shim) vs `int` auto-property with `private set` (upstream) | Shim allows unbounded external mutation; upstream encapsulates mutation behind `StopAutoPick`/`ResumeAutoPick` |
| Static singleton with `new()` default ctor (shim) vs `Activator.CreateInstance` via `Singleton<T>` (upstream) | Equivalent for this case |
| No `Reset()` | Shim state persists forever — no cleanup mechanism |
| No `Clear()` | Same |
| No `DestroyInstance()` | Instance lives for process lifetime |

**What the shim DOES correctly:**

- Provides type resolution for `RunnerContext.Instance.AutoPickTriggerStopCount` in Core
- Uses Thread-Safe singleton pattern
- `volatile` ensures cross-thread visibility of the stop count

### 9.6 Architecture classification (corrected)

#### 9.6.1 Role classification

The upstream `RunnerContext` is a **mutable execution state object + service locator**:
- **Mutable execution state** (primary): `IsSuspend`, `IsPreExecution`, `IsContinuousRunGroup`, `PartyName`, `AutoPickTriggerStopCount`, `isAutoFetchDispatch`, `SuspendableDictionary`
- **Service locator / lazy provider** (secondary): `GetCombatScenes(CancellationToken)` wraps `CaptureToRectArea()`, OCR, and team initialization — effectively a service locator for the combat scene
- **Lifecycle management**: `Clear()` / `Reset()` / `DestroyInstance()`

The Core shim is a **Category C/E transitional shim**:
- Exists only to satisfy a single compiled type reference in one linked file (`AutoPickTrigger.cs` line 66)
- Provides a minimal `AutoPickTriggerStopCount` with `volatile` semantics
- Will become deletable only after the nullable `IAutoPickRuntimeState?` fallback is replaced with a required `IAutoPickRuntimeState` constructor injection across ALL call sites
- Does NOT satisfy "dead shim" criteria yet — the null-coalescing fallback (`?? RunnerContext.Instance...`) is compiled into Core even if macOS composition never reaches it

#### 9.6.2 Question answers

| # | Question | Answer |
|---|----------|--------|
| 1 | Who creates it? | The shim is created by its own double-checked-lock singleton getter. On macOS, it is never accessed at runtime (dead branch). On Windows WPF, upstream's `Singleton<RunnerContext>.Instance` creates via `Activator`. |
| 2 | Who holds it? | Static field `_instance`. WPF `TaskRunner` and `ScriptService` hold references via `Instance` property. |
| 3 | Who modifies it? | **Upstream**: `TaskRunner`, `ScriptService`, `PathExecutor`, `TaskControl`, `AutoFightTask`, `ScriptControlViewModel`, `HotKeyViewModel`, `AutoPickTrigger` etc. **Shim**: no runtime mutations on macOS (dead branch). |
| 4 | Lifecycle scope? | **App-level singleton** — exists for entire process lifetime. Not task-scoped despite `Clear()`/`Reset()` methods. |
| 5 | Required constructor parameter? | Not currently. Its `Instance` property is the universal entry point. |
| 6 | Should split into narrow interfaces? | **Yes** — upstream's responsibilities (execution state, combat scene provider, pause/suspend, pre-execution flag) are distinct. `IAutoPickRuntimeState` already split the AutoPick stop count. For macOS, only the AutoPick stop count is relevant. |
| 7 | Belongs in Platform.Abstractions? | No — it's execution state, not a platform capability. |
| 8 | References Core types? | **Upstream** references `CombatScenes`, `CaptureToRectArea()` — these are WPF business types, not Core contracts. The shim references nothing. |
| 9 | Should macOS create a corresponding object? | No — the single consumed member (`AutoPickTriggerStopCount`) is already provided via `IAutoPickRuntimeState` / `MacAutoPickRuntimeState`. |
| 10 | Replaceable by CancellationToken / narrow state interface? | **Yes** — for Core purposes, `IAutoPickRuntimeState.StopCount` already covers the only consumed member. CancellationToken covers cancellation, `IProgress<T>` covers progress. |

#### 9.6.3 Architecture rule compliance

| Rule | RunnerContext violation | Severity |
|------|------------------------|----------|
| No static gateway | ✅ Upstream: `Singleton<T>.Instance` is a static gateway by convention. The shim replicates this. | ⚠️ Pre-existing pattern, not introduced by shim |
| No service locator | ⚠️ Upstream: `GetCombatScenes()` wraps capture+OCR+team init — service locator pattern. The shim does NOT include this. | ⚠️ Upstream issue, shim is clean |
| No IServiceProvider in business layer | ✅ Neither upstream nor shim exposes IServiceProvider | ✅ |
| No fallback singleton resolution | ❌ **AutoPickTrigger line 66:** `RunnerContext.Instance.AutoPickTriggerStopCount` is a static singleton fallback for `IAutoPickRuntimeState` | High — violates "required capability must be constructor injection" |
| Consumer depends on narrow interface | ⚠️ The consumer (`AutoPickTrigger`) already prefers `IAutoPickRuntimeState` but keeps the static fallback | Medium |
| No null!/dummy/no-op half-valid state | ✅ The shim provides a valid `int` value (0) | ✅ |
| Must keep upstream WPF behavior | ❌ **Current recommendation (`?? 0`) would CHANGE Windows null-runtimeState behavior** | High — rejected |

**Specific violations identified:**

1. **Global mutable state**: `RunnerContext.Instance.AutoPickTriggerStopCount` is mutable static state. The upstream at least encapsulates write via `private set`, but the shim uses `public volatile int field` — no write encapsulation.

2. **Contract contradiction (documented in §9.10)**:
   > AutoPickTrigger constructor comment: "All injected dependencies are required — no static fallback."
   > But `_runtimeState` is declared `IAutoPickRuntimeState?` (nullable), constructor accepts `null`, and `StopCount` falls back to `RunnerContext.Instance`. The contract and implementation conflict.

3. **Hidden lifecycle ownership**: None for the shim — it's never accessed at runtime on macOS.

4. **Shared state across unrelated tasks**: `AutoPickTriggerStopCount` is global across all triggers. This is a WPF concern, not a Core concern since the Core code path uses injected `IAutoPickRuntimeState`.

5. **No fake initialized state**: The shim's default `AutoPickTriggerStopCount = 0` is correct.

### 9.7 Recommendation (corrected)

**Category C/E: Replace nullable RunnerContext fallback with required IAutoPickRuntimeState constructor injection. Keep shim until every constructor call site is migrated.**

Only after ALL call sites pass a non-null runtime state, upgrade to **Category F — remove dead shim**.

**Not accepted: `?? 0`** — replacing a static singleton fallback with a magic-default fallback does not address the root cause. It would silently change Windows null-runtimeState behavior (previously reflecting `StopAutoPick()` mutations; now permanently returning 0).

**Alternative considered (Category B — link upstream):** Rejected because the upstream `RunnerContext` has heavy WPF/task dependencies (`CombatScenes`, `CaptureToRectArea()`, `ISuspendable`, `TaskProgress`) that cannot be linked into Core.

### 9.8 AutoPickTrigger constructor call sites (complete audit)

18 total call sites found:

| # | File | Project | Preprocessing | `runtimeState` arg | Status |
|---|------|---------|---------------|-------------------|--------|
| 1 | `MacAutoPickComposition.cs:64` | Core (production) | `BGI_PLATFORM_MAC` | `runtimeState` (non-null, guarded by `ThrowIfNull`) ✅ | MacAutoPickRuntimeState |
| 2 | `Shim/GameTaskManager.cs:58-59` | Core (production) | `BGI_PLATFORM_MAC` | `null` ❌ — hardcoded | No adapter passed |
| 3 | `GameTask/GameTaskManager.cs:54` | WPF (production) | `BGI_FULL_WINDOWS` | `null` ❌ — hardcoded | Should use WindowsAutoPickRuntimeState |
| 4 | `GameTask/GameTaskManager.cs:105` | WPF (production) | `BGI_FULL_WINDOWS` | `null` ❌ — hardcoded | Should use WindowsAutoPickRuntimeState |
| 5 | `Program.cs:201` | Verification | none | `state0B5` (non-null) ✅ | MacAutoPickRuntimeState(0) |
| 6 | `Program.cs:208` | Verification | none | `stateForB5` (non-null) ✅ | MacAutoPickRuntimeState(2) |
| 7 | `Program.cs:214` | Verification | none | `null` ❌ | Tests null semantics |
| 8 | `Program.cs:225` | Verification | none | `null` ❌ | Tests externalConfig-only |
| 9 | `Program.cs:234` | Verification | none | `stateForB5` (non-null) ✅ | MacAutoPickRuntimeState(2) |
| 10 | `Program.cs:243` | Verification | none | `null` ❌ | null inputBackend throw test |
| 11 | `Program.cs:246` | Verification | none | `null` ❌ | null configProvider throw test |
| 12 | `Program.cs:611` | Verification | none | `null` ❌ | B8.1.1 inputBackend test |
| 13 | `Program.cs:675` | Verification | none | `null` ❌ | B8.3A config field test |
| 14 | `Program.cs:685` | Verification | none | `null` ❌ | B8.3C disabled test |
| 15 | `Program.cs:691` | Verification | none | `null` ❌ | B8.3C enabled test |
| 16 | `Program.cs:699` | Verification | none | `null` ❌ | B8.3D blacklist off test |
| 17 | `Program.cs:743` | Verification | none | `null` ❌ | null paddle throw test |
| 18 | `Program.cs:745` | Verification | none | `null` ❌ | null yap throw test |

**Summary:**
- 4 call sites pass a non-null `IAutoPickRuntimeState` (all verification or macOS composition)
- 14 call sites pass `null` (both WPF production paths and verification)
- 0 call sites use reflection or `Activator.CreateInstance` for AutoPickTrigger

**Core compilation closure call sites (after preprocessing):**
- `MacAutoPickComposition.cs:64` — non-null ✅
- `Shim/GameTaskManager.cs:58-59` — **null ❌ — must be migrated**

### 9.9 Contract contradiction

**Current code** (AutoPickTrigger.cs lines 55, 65-66, 71-94):

```csharp
private readonly IAutoPickRuntimeState? _runtimeState;  // nullable field

/// Master constructor. All injected dependencies are required — no static fallback.
public AutoPickTrigger(
    AutoPickExternalConfig? config,
    IAutoPickRuntimeState? runtimeState,   // nullable parameter
    ...
)
{
    ...
    _runtimeState = runtimeState;  // stores null without guard
    ...
}

private int StopCount =>
    _runtimeState?.StopCount ?? RunnerContext.Instance.AutoPickTriggerStopCount;
    // keeps a static-fallback escape hatch
```

**Claimed contract:** "All injected dependencies are required — no static fallback."
**Actual contract:** `IAutoPickRuntimeState` is optional; `RunnerContext.Instance` is the implicit fallback.

**Target contract:**
```csharp
private readonly IAutoPickRuntimeState _runtimeState;  // non-nullable field

public AutoPickTrigger(
    AutoPickExternalConfig? config,
    IAutoPickRuntimeState runtimeState,    // required parameter
    ...
)
{
    ArgumentNullException.ThrowIfNull(runtimeState);
    ...
    _runtimeState = runtimeState;
}

private int StopCount => _runtimeState.StopCount;  // no fallback, no null propagation
```

### 9.10 Windows adapter wiring

**`WindowsAutoPickRuntimeState`** (`BetterGenshinImpact/Core/Runtime/Windows/WindowsAutoPickRuntimeState.cs`):

```csharp
public sealed class WindowsAutoPickRuntimeState : IAutoPickRuntimeState
{
    public int StopCount => GameTask.RunnerContext.Instance.AutoPickTriggerStopCount;
}
```

This is the correct bridge between `IAutoPickRuntimeState` and the upstream `RunnerContext` singleton. It lives in the `BetterGenshinImpact` (WPF) project.

**Current wiring status:**

| Entry point | Uses `WindowsAutoPickRuntimeState`? | Status |
|-------------|--------------------------------------|--------|
| `GameTaskManager.cs` init (line 54) | ❌ passes `null` | **Must be migrated** |
| `GameTaskManager.cs` AddTrigger (line 105) | ❌ passes `null` | **Must be migrated** |
| DI composition root (`App.xaml.cs`) | No evidence of current `IAutoPickRuntimeState` DI registration | **Needs verification** |

**WPF `GameTaskManager` both call sites** pass `null` for `runtimeState`. They can be changed to pass `new WindowsAutoPickRuntimeState()` without modifying any other WPF code — the adapter's `StopCount` already delegates to the upstream `RunnerContext.Instance.AutoPickTriggerStopCount` that those call sites previously read directly via the fallback.

### 9.11 Reachability conclusion (corrected)

The `RunnerContext.Instance.AutoPickTriggerStopCount` fallback is **dead code on macOS** because `MacAutoPickComposition.Compose` always provides a non-null `IAutoPickRuntimeState`. However:

**The fallback is NOT globally dead.** It is reachable in:
1. **WPF production** — both `GameTaskManager.cs` call sites pass `null` for `runtimeState`, so the fallback fires on every AutoPickTrigger usage
2. **Core GameTaskManager shim** (`Shim/GameTaskManager.cs:58-59`) — hardcodes `null`, so the fallback fires in the Core shim too
3. **Verification tests** — 10+ call sites pass `null` to test null-field behavior

**Correct statement:** "The macOS supported composition path never evaluates the RunnerContext fallback. But the fallback is still live in WPF production, the Core shim's GameTaskManager, and verification tests. It will only become globally dead after all call sites pass a non-null `IAutoPickRuntimeState`."

### 9.12 Corrected implementation plan

#### B10.6.1 — Make IAutoPickRuntimeState required in AutoPickTrigger, migrate all call sites

**Scope:** Only migration. The RunnerContext shim and its csproj entry remain present.

| Step | File | Change |
|------|------|--------|
| 1a | `GameTask/AutoPick/AutoPickTrigger.cs` field | `IAutoPickRuntimeState? _runtimeState` → `IAutoPickRuntimeState _runtimeState` (non-nullable) |
| 1b | `GameTask/AutoPick/AutoPickTrigger.cs` constructor | `IAutoPickRuntimeState? runtimeState` → `IAutoPickRuntimeState runtimeState` + `ArgumentNullException.ThrowIfNull(runtimeState)` |
| 1c | `GameTask/AutoPick/AutoPickTrigger.cs` StopCount | `_runtimeState?.StopCount ?? RunnerContext.Instance...` → `_runtimeState.StopCount` |
| 1d | `GameTask/AutoPick/AutoPickTrigger.cs` comment | Remove `/// fall back to RunnerContext...` comment |
| 2 | `Core/Shim/GameTaskManager.cs:58-59` | Add `IAutoPickRuntimeState runtimeState` parameter to `AddTrigger` (alongside existing `IInputBackend`, `ISystemInfo`, etc.); pass it through to the `AutoPickTrigger` constructor instead of `null` |
| 3 | `Core/Composition/MacAutoPickComposition.cs:64` | Already passes non-null `runtimeState` — unchanged |
| 4 | **WPF** `GameTask/GameTaskManager.cs:54` (LoadInitialTriggers) | Add `IAutoPickRuntimeState runtimeState` parameter; pass it to `new AutoPickTrigger(..., runtimeState, ...)` |
| 5 | **WPF** `GameTask/GameTaskManager.cs:105` (AddTrigger) | Add `IAutoPickRuntimeState runtimeState` parameter; pass it to `new AutoPickTrigger(..., runtimeState, ...)` |
| 6 | **WPF** `GameTask/TaskTriggerDispatcher.cs` — constructor | Add `IAutoPickRuntimeState runtimeState` parameter; store as field `_runtimeState` |
| 7 | **WPF** `TaskTriggerDispatcher.Start()` (line 188) | Pass `_runtimeState` to `GameTaskManager.LoadInitialTriggers(...)` |
| 8 | **WPF** `TaskTriggerDispatcher.AddTrigger()` (line 141) | Pass `_runtimeState` to `GameTaskManager.AddTrigger(...)` |
| 9 | **WPF** `TaskTriggerDispatcher.ReloadInitialTriggers()` (line 158) | Pass `_runtimeState` to `GameTaskManager.LoadInitialTriggers(...)` |
| 10 | **WPF** `App.xaml.cs` DI registration (line 166) | Already registered: `services.AddSingleton<IAutoPickRuntimeState, WindowsAutoPickRuntimeState>()`. Verify it remains unchanged, do **not** add a duplicate registration. DI injects it into `TaskTriggerDispatcher` automatically. |
| 11 | `Verification/Program.cs` | See §9.13 for categorized migration |

**Rules enforced:**
- GameTaskManager (both Core shim and WPF) **receives** `IAutoPickRuntimeState`, never creates it
- TaskTriggerDispatcher receives `IAutoPickRuntimeState` via DI, stores as field, passes to GameTaskManager
- WindowsAutoPickRuntimeState is created **only** in the DI composition root (App.xaml.cs)
- No optional/default runtimeState — all callers must provide one

#### B10.6.2 — Source guard + delete shim (independent commit)

**Scope:** Only shim file deletion. No behavioral changes.

| Step | File | Change |
|------|------|--------|
| 1 | — | Run `rg '\bRunnerContext\b' BetterGenshinImpact.Core/ --type cs` | expect zero production refs |
| 2 | `BetterGenshinImpact.Core/Shim/RunnerContext.cs` | Delete file |
| 3 | `BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj` | Remove `<Compile Include="Shim/RunnerContext.cs" />` |
| 4 | — | `dotnet build BetterGenshinImpact.Core.csproj` — zero errors |
| 5 | — | `dotnet run` on Verification project — all pass |
| 6 | — | WPF type-resolution check: `rg 'RunnerContext'` in WPF project — still resolves to upstream definition |
| 7 | — | Shim count: 16 → **15** |

**B10.6.1 and B10.6.2 are two separate implementation commits.** Do not merge them or delete the shim in B10.6.1.

### 9.13 Verification migration strategy (categorized)

| Category | Current pattern | Count | Action | Expected assertion count |
|----------|----------------|-------|--------|--------------------------|
| A — Unrelated test that happens to pass `null` | `new AutoPickTrigger(ext, null, prov, input, sys, pad, yap)` | 9 sites (lines 214, 225, 243, 246, 611, 675, 685, 691, 699) | Replace `null` with `new MacAutoPickRuntimeState(0)`. No assertion changes needed — these tests verify inputBackend, configProvider, recognizers, not runtimeState. | Unchanged |
| B — Test that explicitly verifies null fallback behavior | `Assert("has null _runtimeState", stateNull == null)` + `Assert("externalConfig-only has null _runtimeState", ...)` | 2 assertions (lines 219-220, 229) | Replace with **2** required-dependency guard assertions: (1) `try { new AutoPickTrigger(ext, null!, ...); Assert("null rt should throw", false,""); } catch (ArgumentNullException) { Assert("null rt → ArgumentNullException", true,""); }` and (2) one assertion confirming `_externalConfig` remains nullable (extField still null when externalConfig param is null — externalConfig stays nullable). | Same count, 2 → 2 |
| C — Combined/null-other-dep test | `new AutoPickTrigger(null, null, prov, null!, ...)` — tests null inputBackend | 2 sites (lines 243, 246) | Replace `null` with `MacAutoPickRuntimeState(0)` so the intended dependency (inputBackend, configProvider) remains the first to fail | Unchanged |
| D — null paddle/yap guard | `new AutoPickTrigger(null, null, prov, rec, sys, null!, yap)` | 2 sites (lines 743, 745) | Replace `null` with `MacAutoPickRuntimeState(0)` | Unchanged |

**Expected total assertions:** 112 — unchanged from baseline. Category B replaces 2 null-field assertions with 2 required-dependency guard assertions. Categories A/C/D are mechanical null→MacAutoPickRuntimeState(0) replacements that affect no assertion count. No decrease without explicit reason.

### 9.14 B10.6.1 gate

After B10.6.1 completes, the following must all hold:

- [ ] `AutoPickTrigger._runtimeState` field: non-nullable (`IAutoPickRuntimeState`, not `IAutoPickRuntimeState?`)
- [ ] `AutoPickTrigger` constructor: `IAutoPickRuntimeState runtimeState` with `ArgumentNullException.ThrowIfNull(runtimeState)`
- [ ] `StopCount`: `_runtimeState.StopCount` (no fallback)
- [ ] `AutoPickTrigger.cs` comment no longer references `RunnerContext`
- [ ] All production call sites pass non-null `IAutoPickRuntimeState`
- [ ] Core GameTaskManager shim passes its `runtimeState` parameter to `AutoPickTrigger` (not null)
- [ ] WPF GameTaskManager passes its `runtimeState` parameter to `AutoPickTrigger` (not null)
- [ ] TaskTriggerDispatcher stores `IAutoPickRuntimeState` as field and passes it to GameTaskManager
- [ ] App.xaml.cs existing DI registration verified (line 166); no duplicate registration added
- [ ] All Verification call sites use valid non-null runtimeState except category-B explicit null-guard tests
- [ ] `rg '\bRunnerContext\b' BetterGenshinImpact.Core/ --type cs` — zero production references (comments excluding MacCoreRuntimeAdapter.cs line 9 remain)
- [ ] `BetterGenshinImpact.Core/Shim/RunnerContext.cs` — file still present
- [ ] Core csproj entry for `Shim/RunnerContext.cs` — still present
- [ ] `dotnet build BetterGenshinImpact.Core.csproj` — zero errors
- [ ] Verification — all pass
- [ ] WPF build/type-resolution check — no new errors

### 9.15 B10.6.2 gate

- [ ] `rg '\bRunnerContext\b' BetterGenshinImpact.Core/ --type cs` — zero production references
- [ ] Verification references to RunnerContext — zero
- [ ] `BetterGenshinImpact.Core/Shim/RunnerContext.cs` — deleted
- [ ] Core csproj entry removed
- [ ] `dotnet build BetterGenshinImpact.Core.csproj` — zero errors
- [ ] Verification — all pass; assertion total 112, unchanged from baseline
- [ ] WPF still resolves upstream `RunnerContext` (`GameTask/RunnerContext.cs`)
- [ ] Shim count: 16 → **15**

### 9.16 Behavior preservation table

| Scenario | `_runtimeState` | `StopCount` before | `StopCount` after | Delta |
|----------|----------------|--------------------|-------------------|-------|
| macOS, MacAutoPickComposition | `MacAutoPickRuntimeState(0)` | 0 (injected) | 0 (injected) | ✅ None |
| macOS, MacAutoPickRuntimeState(2) | `MacAutoPickRuntimeState(2)` | 2 (injected) | 2 (injected) | ✅ None |
| WPF, with WindowsAutoPickRuntimeState | `WindowsAutoPickRuntimeState` | upstream `RunnerContext` value | upstream `RunnerContext` value | ✅ None |
| **WPF, null runtimeState (legacy)** | **null** | **RunnerContext.Instance value (may be >0)** | **Must not silently redefine as 0** ⛔ | Must migrate call site |
| **Core GameTaskManager shim, null** | **null** | **RunnerContext shim value (always 0)** | **Must not silently redefine as 0** ⛔ | Must migrate call site |
| Verification, null runtimeState | null | 0 (via shim) | Must not pass null | Replace with MacAutoPickRuntimeState(0) |
| Verification, null inputBackend test | null | tests throw | Same | Pass MacAutoPickRuntimeState(0) |
| Verification, null configProvider test | null | tests throw | Same | Pass MacAutoPickRuntimeState(0) |

**Null legacy paths (must be migrated, not redefined):**
- WPF `GameTaskManager` init: pass `WindowsAutoPickRuntimeState`
- WPF `GameTaskManager.AddTrigger`: pass `WindowsAutoPickRuntimeState`
- Core `GameTaskManager` shim: accept `IAutoPickRuntimeState` parameter

### 9.17 Neighboring shim relationship

| Shim | Relationship with RunnerContext | Ordering constraint |
|------|-------------------------------|---------------------|
| `TaskControl.cs` | Core `Shim/TaskControl.cs` does NOT reference RunnerContext | **No dependency** |
| `GameTaskManager.cs` | Core shim's `AddTrigger` hardcodes `null` for runtimeState — **requires migration in B10.6.1 step 2** | **Must be modified during B10.6.1** |
| `Global.cs` | No RunnerContext reference | Independent |
| `PlatformServices.cs` | No RunnerContext reference | Independent |
| `App.cs` | No RunnerContext reference | Independent |
| `TaskContext.cs` | Already deleted in B10.5.4 | Already resolved |

The `GameTaskManager` shim is the only neighboring shim that interacts with this audit's implementation. Its `AddTrigger` signature must gain an `IAutoPickRuntimeState` parameter. The `GameTaskManager` shim itself is not deleted — only its `null` runtimeState hardcode is replaced.

**WPF composition ownership chain (as discovered):**

```
App.xaml.cs existing DI registration (line 166)
  services.AddSingleton<IAutoPickRuntimeState, WindowsAutoPickRuntimeState>()
  → TaskTriggerDispatcher constructor receives IAutoPickRuntimeState (new param)
  → stores _runtimeState field
  → Start(): passes _runtimeState to GameTaskManager.LoadInitialTriggers()
  → AddTrigger(): passes _runtimeState to GameTaskManager.AddTrigger()
  → ReloadInitialTriggers(): passes _runtimeState to GameTaskManager.LoadInitialTriggers()
```

- `TaskTriggerDispatcher` is the WPF composition entry point for triggers
- It already stores `_inputBackend`, `_autoPickConfigProvider`, `_paddleRecognizer`, `_yapRecognizer` as constructor-injected fields via DI
- The new `IAutoPickRuntimeState _runtimeState` field follows the same pattern
- `WindowsAutoPickRuntimeState` is created **once** by DI and injected into `TaskTriggerDispatcher`
- Neither `GameTaskManager` (WPF) nor `GameTaskManager` (Core shim) creates `WindowsAutoPickRuntimeState`

### 9.18 Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Windows null-runtimeState call sites not fully migrated before B10.6.1 closes | **High** — would change legacy behavior | Tracked in B10.6.1 gate (§9.14); all call sites audited in §9.8 |
| Core GameTaskManager shim's `AddTrigger` signature change breaks non-Core callers | **Medium** — must verify no other callers exist | Search `AddTrigger` in Core closure; `MacAutoPickComposition` does not call AddTrigger, only `Compose()` directly |
| Verification tests with null assertions need careful categorization | **Low** — mechanical replacement, tracked in §9.13 | Category A/B/C/D applied per site |
| Rebase conflict with upstream changes to AutoPickTrigger constructor | **Low** — single-file change, easy to rebase | None |
| TaskTriggerDispatcher DI registration change in App.xaml.cs affects unrelated trigger components | **Medium** — only adds `IAutoPickRuntimeState` registration, no existing registrations removed | DI container handles additive changes safely |

### 9.19 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 112/112 ✅
```

### 9.20 B10.6.1 Implementation Result

| Metric | Before | After |
|--------|--------|-------|
| `AutoPickTrigger._runtimeState` type | `IAutoPickRuntimeState?` (nullable) | `IAutoPickRuntimeState` (required) |
| `AutoPickTrigger` constructor param | `IAutoPickRuntimeState?` (nullable) | `IAutoPickRuntimeState` (required) + `ArgumentNullException.ThrowIfNull` |
| `StopCount` implementation | `_runtimeState?.StopCount ?? RunnerContext.Instance.AutoPickTriggerStopCount` | `_runtimeState.StopCount` |
| `RunnerContext` reference in AutoPickTrigger | 1 (fallback at line 66) | **0** — removed |
| Core shim `GameTaskManager.AddTrigger` runtimeState param | `null` hardcoded | Required `IAutoPickRuntimeState` parameter, forwarded to trigger |
| WPF `GameTaskManager.LoadInitialTriggers` runtimeState param | `null` hardcoded | Required `IAutoPickRuntimeState` parameter, forwarded |
| WPF `GameTaskManager.AddTrigger` runtimeState param | `null` hardcoded | Required `IAutoPickRuntimeState` parameter, forwarded |
| `TaskTriggerDispatcher` constructor | No runtime state | `IAutoPickRuntimeState runtimeState` param, stored as `_runtimeState` |
| `TaskTriggerDispatcher` call sites | Passed no runtime state | All three pass `_runtimeState` to GameTaskManager |
| `App.xaml.cs` DI registration | `IAutoPickRuntimeState → WindowsAutoPickRuntimeState` (line 166) | **Unchanged** — verified existing, no duplicate added |
| Verification assertion count | 112 | **112** (2 null-field assertions replaced with 2 required-dependency guard assertions) |
| `RunnerContext` shim file | `Shim/RunnerContext.cs` | **Retained** (not deleted) |
| Core csproj shim entry | `<Compile Include="Shim/RunnerContext.cs" />` | **Retained** (not deleted) |
| Source guard: `AutoPickTriggerStopCount` | Core 1 hit | Zero production hits ✅ |
| Source guard: `IAutoPickRuntimeState?` | AutoPickTrigger field + ctor | Zero hits ✅ |
| Source guard: `null` runtimeState in production call | 4 sites | Zero hits ✅ (guard test uses `null!` only) |
| Core build | 0 errors | **0 errors** ✅ |
| Core Verification | 112/112 | **112/112** ✅ |
| WPF build — new errors from this change | — | **Zero** — 4 pre-existing errors (IInputBackend/ISystemInfo resolution, same original unmodified code) remain |
| Shim count | 16 | **16** (unchanged, RunnerContext shim retained) |

### 9.21 B10.6.2 Implementation Result

| Metric | Before | After |
|--------|--------|-------|
| Core shim `Shim/RunnerContext.cs` | Exists (30 lines) | **Deleted** ✅ |
| Core csproj `Shim/RunnerContext.cs` entry | Present | **Removed** ✅ |
| Upstream RunnerContext link added? | — | **No** — upstream is WPF-host-only, not suitable for Core |
| Core RunnerContext type definition | Shim | **Zero** — only WPF `GameTask/RunnerContext.cs` remains ✅ |
| Core production code RunnerContext refs | Shim self-definition only | **Zero** ✅ |
| Verification RunnerContext refs | Zero | **Zero** ✅ |
| Csproj RunnerContext entry | Present | **Removed** ✅ |
| `MacCoreRuntimeAdapter.cs` comment | `"no reference to TaskContext, RunnerContext, or Windows APIs"` | **Unchanged** — comment remains, not a symbol reference |
| `WindowsAutoPickRuntimeState` | Delegates to upstream `GameTask.RunnerContext` | **Unchanged** — correct WPF behavior ✅ |
| WPF upstream `GameTask/RunnerContext.cs` | — | **Unchanged** ✅ |
| Core build | 0 errors | **0 errors** ✅ |
| Core Verification | 112/112 | **112/112** ✅ |
| WPF build — new errors from shim deletion | — | **Zero** — same 4 pre-existing errors as B10.6.1; no RunnerContext/DI/constructor errors added ✅ |
| Shim count | 16 | **15** ✅ |
| B10.6 status | B10.6.1 complete, shim retained | **B10.6 complete** ✅ |

---

## 10. B10.7 Audit: PlatformServices

### 10.1 Current shim

| Aspect | Detail |
|--------|--------|
| File | `BetterGenshinImpact.Core/Shim/PlatformServices.cs` |
| Lines | 12 |
| Namespace | `BetterGenshinImpact` |
| Type kind | `public static class PlatformServices` — mutable static gateway |
| Public API | 2 properties |
| `Input` | `public static IInputBackend Input { get; set; } = null!;` — mutable static, default `null!` (uninitialized) |
| `UserInteraction` | `public static IUserInteractionService? UserInteraction { get; set; }` — nullable, unused in Core |
| Comment | `"Static gateway to platform services. Initialized by the host before starting the dispatcher."` |
| Origin | Created in commit `32590fc` (macOS port) — no WPF upstream analog |

### 10.2 Upstream/history investigation

| Aspect | WPF upstream | Core shim |
|--------|-------------|-----------|
| `PlatformServices` class | **Does not exist** in WPF tree | `Shim/PlatformServices.cs` |
| DesktopRegion input access | Refers to `PlatformServices.Input` (same physical file) | Same — DesktopRegion.cs is authoritative in WPF tree, linked in Core |

There is no WPF tree `PlatformServices.cs`. The shim was written for the macOS port to satisfy `DesktopRegion`'s static reference to `PlatformServices.Input`.

**Source file note:** `DesktopRegion.cs` has its authoritative physical source at `BetterGenshinImpact/GameTask/Model/Area/DesktopRegion.cs`. Core compiles it through a linked `<Compile Include=... Link=...>` item. WPF compiles it as its own source file (default SDK glob). PlatformServices has no WPF authoritative definition — WPF currently resolves the public `PlatformServices` type from the referenced Core assembly.

### 10.3 Preprocessed reference table

#### 10.3.1 Core-compiled references

| # | File | Line | Code | Type |
|---|------|------|------|------|
| 1 | `Shim/PlatformServices.cs` | 1–12 | Type definition | Definition |
| 2 | `Shim/Simulation.cs` | 10 | `public static IInputBackend InputBackend => PlatformServices.Input;` | **Consumer** — delegates Simulation to PlatformServices.Input |
| 3 | `GameTask/Model/Area/DesktopRegion.cs` | Core (linked from WPF tree) | 29 | `var input = PlatformServices.Input;` | **Consumer** |
| 4 | `GameTask/Model/Area/DesktopRegion.cs` | Core (linked from WPF tree) | 41 | `PlatformServices.Input.MoveMouseTo(...)` | **Consumer** |
| 5 | `GameTask/Model/Area/DesktopRegion.cs` | Core (linked from WPF tree) | 48 | `var input = PlatformServices.Input;` | **Consumer** |
| 6 | `GameTask/Model/Area/DesktopRegion.cs` | Core (linked from WPF tree) | 58 | `PlatformServices.Input.MoveMouseTo(...)` | **Consumer** |
| 7 | `GameTask/Model/Area/DesktopRegion.cs` | Core (linked from WPF tree) | 63 | `PlatformServices.Input.MoveMouseBy(...)` | **Consumer** |

**Total Core production references: 7** — all reading `PlatformServices.Input`. No Core production code writes to `PlatformServices` (initialize/set).

#### 10.3.2 Verification references

| # | File | Line | Code | Type |
|---|------|------|------|------|
| 1 | `Verification/Program.cs` | 22 | `PlatformServices.Input = recorder;` | **Write** — sets the static gateway for DesktopRegion test |

#### 10.3.3 WPF-only references

The WPF project does not reference `PlatformServices` directly. However, `DesktopRegion.cs` (authoritative physical source in the WPF tree) uses `PlatformServices.Input`. WPF resolves the `PlatformServices` type from the referenced Core assembly. This means:

- WPF DesktopRegion relies on the Core shim's `PlatformServices` for type resolution
- WPF has its own `Simulation.cs` which uses `InputSimulator` (Win32 SendInput, not `PlatformServices`)
- There is no WPF authoritative `PlatformServices` definition — it is entirely a Core shim artifact

### 10.4 Reachability analysis

#### 10.4.1 Compiled reference graph

```
Core compilation closure (BGI_PLATFORM_MAC)
│
├── Shim/PlatformServices.cs ───────── static gateway definition
│   ├── Input: IInputBackend (get/set, mutable, null! default)
│   └── UserInteraction: IUserInteractionService? (unused in Core)
│
├── Shim/Simulation.cs ────────────── delegates via PlatformServices.Input
│   └── IInputBackend → PlatformServices.Input
│       → calls: KeyPress, KeyDown, KeyUp, Scroll, MoveMouseTo, MoveMouseBy, etc.
│
└── DesktopRegion.cs (linked) ─────── 5 static PlatformServices.Input calls
    → DesktopRegionClick(i, x, y, w, h)
    → DesktopRegionMove(i, x, y, w, h)
    → DesktopRegionClick(d cx, d cy)
    → DesktopRegionMove(d cx, d cy)
    → DesktopRegionMoveBy(d dx, d dy)
```

#### 10.4.2 Supported Core runtime graph (macOS AutoPick composition)

```
MacAutoPickComposition.Compose(inputBackend, runtimeState, configProvider, ...)
  → AutoPickTrigger(..., inputBackend, ...)
    → uses _inputBackend field     ← constructor-injected, NOT PlatformServices
  → AutoPickAssets.Initialize(systemInfo, configProvider)
    → uses injected dependencies    ← NOT PlatformServices

DesktopRegion methods:
  → NOT called from AutoPick composition path
  → NOT called from AutoPickTrigger.OnCapture
  → Only reachable if a trigger/task explicitly creates a DesktopRegion
    and calls its instance/static methods

DesktopRegion is linked in Core but its PlatformServices.Input calls
are not on the AutoPick hot path. They are reachable for any code
that constructs a DesktopRegion or invokes its static methods.
```

#### 10.4.3 Verification graph

```
Verification Program.cs
  → PlatformServices.Input = recorder;             ← must set before DesktopRegion
  → DesktopRegion.DesktopRegionMove(960, 540)      ← reads PlatformServices.Input
  → DesktopRegion.DesktopRegionClick(...)           ← reads PlatformServices.Input
```

Verification explicitly sets PlatformServices.Input before desktop-region tests. Without this set, accessing `PlatformServices.Input` would throw `NullReferenceException` (the default value is `null!`).

### 10.5 Semantic analysis

#### Classification: **Category B — replace static PlatformServices usage with explicit IInputBackend dependency**

| Check | Result |
|-------|--------|
| Is it a static gateway? | **Yes** — `PlatformServices.Input` is a mutable static property |
| Is it a service locator? | **Partial** — holds two services; only Input is consumed |
| Does it hide required dependencies? | **Yes** — every consumer silently requires PlatformServices.Input to be set |
| Does it provide null!/dummy default? | **Yes** — `= null!` means uninitialized access => NullReferenceException at runtime |
| Can it be replaced with constructor injection? | **Yes** — `IInputBackend` already exists in `Platform.Abstractions` |
| Need a new narrow interface? | **No** — `IInputBackend` is exactly the right contract |

**Not Category C — no new abstraction needed. Not Category A — 7 Core production references exist.**

### 10.6 DesktopRegion external consumer closure

DesktopRegion is a **geometry + input execution object**, not pure geometry. The authoritative source is `BetterGenshinImpact/GameTask/Model/Area/DesktopRegion.cs`. Core links it via `<Compile Include=... Link=...>`; WPF compiles it as its own source file. PlatformServices has no WPF authoritative definition — WPF resolves it from the referenced Core assembly.

#### 10.6.1 Direct DesktopRegion static method calls

| # | Caller | Project | Preprocessed? | Method | Notes |
|---|--------|---------|---------------|--------|-------|
| 1 | `Region.BackgroundClick()` (line 101) | Core (linked) `#if BGI_FULL_WINDOWS` | ❌ WPF-only | `DesktopRegion.DesktopRegionMove(...)` | Not in Core |
| 2 | `Region.ClickTo()` (line 154) | Core (linked) | ✅ Core | `res.TargetRegion.DesktopRegionClick(...)` | Via ConvertRes<DesktopRegion> |
| 3 | `Region.MoveTo()` (line 189) | Core (linked) | ✅ Core | `res.TargetRegion.DesktopRegionMove(...)` | Via ConvertRes<DesktopRegion> |
| 4 | `GameCaptureRegion.cs` (lines 97, 105, 113) | Core (linked) | ✅ Core | `DesktopRegion.DesktopRegionClick/Move/MoveBy` | 3 call sites |
| 5 | `Verification Program.cs` (line 53, 65) | Test | None | `DesktopRegion.DesktopRegionMove(...)` | 2 call sites |

**Indirect consumers through Region.ClickTo/MoveTo:** Every `region.ClickTo(x,y)` or `region.MoveTo(x,y)` call in the codebase (100+ WPF call sites, ~5 Core call sites) reaches `DesktopRegionClick/Move` through `ConvertRes<T>.ConvertPositionToTargetRegion`.

#### 10.6.2 DesktopRegion constructor and ISystemInfo.DesktopRectArea

| # | Caller | File | Constructor | Has IInputBackend? |
|---|--------|------|-------------|-------------------|
| 1 | `MacSystemInfo.cs:35,49` | Core shim | `new DesktopRegion()` | **No** — uses static DisplayWidth/Height |
| 2 | `SystemInfo.cs:68` (WPF upstream) | Core (linked) | `new DesktopRegion()` | **No** — same pattern |
| 3 | `FakeSystemInfo.cs:18` | UnitTest | `new DesktopRegion(w, h)` | **No** |
| 4 | `GridScreen.cs:464,491` | WPF | `new DesktopRegion(this.input.Mouse)` | **Yes** — passes IInputBackend implicitly via `IMouseSimulator` → ... actually this is a different code path |

The `DesktopRegion` is held by `ISystemInfo.DesktopRectArea` property (`{ get; }`). Both `MacSystemInfo` and upstream `SystemInfo` create it with the parameterless constructor. It is then used as the root region for `Derive()` operations and `ClickTo`/`MoveTo` chain.

#### 10.6.3 Key architectural question answers

| # | Question | Answer |
|---|----------|--------|
| 1 | Is DesktopRegion a pure value/geometry object? | **No** — it combines geometry with input execution (`PlatformServices.Input`) |
| 2 | Would adding `IInputBackend` to constructor pollute all derived region objects? | **Yes** — `GameCaptureRegion : Region`, `ImageRegion : Region` would inherit. But DesktopRegion is where input execution happens; subclasses use `ConvertRes<DesktopRegion>` to delegate input back |
| 3 | Should input capability belong in DesktopRegion itself? | **No** — the current design mixes two concerns. A cleaner split: DesktopRegion remains geometry; input execution is injected or a separate helper |
| 4 | How should static convenience methods be handled? | Preferred: accept `IInputBackend input` as explicit parameter (`DesktopRegion.DesktopRegionMove(input, cx, cy)`). This avoids both the static gateway and the "inject into every region" problem |

### 10.7 Simulation consumer closure

Two distinct Simulation types exist:

| Aspect | WPF authoritative (`Core/Simulator/Simulation.cs`) | Core shim (`Shim/Simulation.cs`) |
|--------|----------------------------------------------------|----------------------------------|
| Input dispatch | `InputSimulator` (Win32 SendInput via Fischless) | `PlatformServices.Input` |
| Static API | `public static InputSimulator SendInput { get; }` | `public static SendInputFacade SendInput { get; }` |
| Key/Mouse facades | Real Win32 implementation | Delegates to `Simulation.InputBackend` (= `PlatformServices.Input`) |
| `ReleaseAllKey()` | Real implementation | Throws `NotSupportedException` |

#### 10.7.1 Simulation consumers in Core closure

| # | Caller | File | Line(s) | Preprocessed? | Has own IInputBackend? |
|---|--------|------|---------|---------------|------------------------|
| 1 | `GlobalMethod.cs` (linked) | `BetterGenshinImpact/Core/Script/Dependence/` | 41–250 | ✅ Core (no `#if`) | **No** — uses `Simulation.SendInput.Mouse.LeftButtonDown()` etc. |
| 2 | `AutoLeyLineOutcropTask.cs` | `BetterGenshinImpact` | 928, 949, ... | ❌ WPF-only | Uses WPF authoritative Simulation |

**Verification consumers of Core simulation shim:** Zero. Verification uses `RecordingInputBackend` directly and tests through `AutoPickTrigger`, not through the Simulation facade.

**Key finding:** The only Core production consumer of the Simulation shim is `GlobalMethod.cs` (linked shared source). `AutoLeyLineOutcropTask` references the WPF authoritative Simulation, not the Core shim.

### 10.8 Relation to neighboring shims

| Shim | Relationship | Ordering |
|------|-------------|----------|
| `Simulation.cs` | **Depends on** `PlatformServices.Input` — its entire facade delegates through this static | Must be resolved before or with PlatformServices deletion |
| `DesktopRegion.cs` | **Depends on** `PlatformServices.Input` — 5 internal calls | Must be resolved before or with PlatformServices deletion |
| `MacSystemInfo.cs` | Creates `new DesktopRegion()` — no `IInputBackend` passed | Must be updated when DesktopRegion constructor changes |
| `Global.cs` | No direct reference to PlatformServices | Independent |
| `App.cs` | No direct reference | Independent |
| `GameTaskManager.cs` | Receives `IInputBackend` via parameter | Independent |
| `TaskControl.cs` | No reference | Independent |
| `GlobalMethod.cs` | Uses `Simulation.SendInput` — transitively via Simulation shim -> PlatformServices | Must be resolved as part of Simulation migration |

### 10.9 Recommendation

**Category B — replace static PlatformServices usage with explicit IInputBackend dependency.**

`IInputBackend` already exists in `Platform.Abstractions`. No new interface needed. The challenge is the migration scope: DesktopRegion is used extensively as the terminal input dispatch point in the `Region.ClickTo() -> ConvertRes<DesktopRegion> -> DesktopRegionClick -> PlatformServices.Input` chain.

### 10.10 Revised minimal implementation plan

#### B10.7.1: Add IInputBackend parameter to DesktopRegion static methods

Replace:
```csharp
public static void DesktopRegionMove(double cx, double cy) =>
    PlatformServices.Input.MoveMouseTo(...);
```
With:
```csharp
public static void DesktopRegionMove(IInputBackend input, double cx, double cy) =>
    input.MoveMouseTo(...);
```

Same for `DesktopRegionClick(double, double)` and `DesktopRegionMoveBy(double, double)`.

**Consumers to update in this step:**
- `GameCaptureRegion.cs` (3 sites, Core linked) — passes its caller's injected `_inputBackend` or forward from Region
- `Region.cs` `ClickTo`/`MoveTo` (2 sites, Core linked) — needs `input` from call chain
- `Verification Program.cs` (2 sites) — passes `recorder` directly

**API signature decision:**
- DesktopRegion retains `IInputBackend` parameter — no static gateway, no instance field pollution
- All callers are explicit about which input backend they use
- The parameter is always available: `GameCaptureRegion` callers have `_inputBackend` from their trigger/task context

**Impact:**
- Core: 5 call sites updated
- WPF: ~100+ indirect `ClickTo`/`MoveTo` call sites — but those flow through `Region.ClickTo()` which calls `ConvertRes<DesktopRegion>`, which calls `TargetRegion.DesktopRegionClick`. `TargetRegion` is a `DesktopRegion` instance. The instance methods (`DesktopRegionClick(int,int,int,int)`) would need `IInputBackend` too.
- Verification: 2 static call sites updated

**Gate:** Core build 0 errors, Verification 112/112.

#### B10.7.2: Add IInputBackend to DesktopRegion instance methods

The instance methods `DesktopRegionClick(int x, int y, int w, int h)` and `DesktopRegionMove(int x, int y, int w, int h)` also use `PlatformServices.Input`. These are called through the `Region.ClickTo()` / `Region.MoveTo()` chain.

**Option (recommended):** Keep instance methods but add `IInputBackend input` parameter:
```csharp
public void DesktopRegionClick(IInputBackend input, int x, int y, int w, int h)
```
Update `Region.ClickTo()` to accept and forward `IInputBackend` from its caller.

This avoids requiring DesktopRegion constructor to hold IInputBackend (which would cascade into ISystemInfo.DesktopRectArea construction and every `new DesktopRegion()` call site in the codebase).

**Consumers to update:** Region.cs ClickTo/MoveTo call sites.

**Gate:** Core build 0 errors, Verification 112/112.

#### B10.7.3: Replace Simulation shim InputBackend delegation

`GlobalMethod.cs` (linked, Core closure) is the only Core production consumer of `Simulation.SendInput`. Each call does:
```csharp
Simulation.SendInput.Mouse.LeftButtonDown();
```

Each such call can be replaced with the caller's existing `IInputBackend` (if available) or an equivalent `_inputBackend.LeftButtonDown()`.

If the caller does not already have `IInputBackend`, inject it — this follows the same required-dependency pattern established in B10.6.1.

The Simulation shim itself then has no production consumers and can be deleted alongside PlatformServices.

**Gate:** Core build 0 errors, Verification 112/112, zero Simulation references in Core production.

#### B10.7.4: Delete PlatformServices + Simulation shims after zero-reference guard

When B10.7.1–3 produce:
- `rg '\bPlatformServices\b' BetterGenshinImpact.Core Test/ --type cs` → zero production refs (MacCoreRuntimeAdapter comment remains)
- `rg '\bSimulation\b' BetterGenshinImpact.Core Test/BetterGenshinImpact.Core.Verification --type cs` → zero production refs
- Verification no longer sets `PlatformServices.Input = recorder`

Then delete:
- `BetterGenshinImpact.Core/Shim/PlatformServices.cs`
- `BetterGenshinImpact.Core/Shim/Simulation.cs`
- Both csproj entries
- `PlatformServices.Input = recorder;` from Verification (replaced with direct `IInputBackend` parameter)

**Shim count reduction:** 15 → **13**.

**Gate:** Core build 0 errors, Verification 112/112, WPF check shows no new errors.

### 10.11 Key architecture constraints

| Constraint | Rule |
|------------|------|
| No static gateway wrapper | Verification must NOT use a helper that still sets PlatformServices privately |
| No constructor cascade | DesktopRegion constructor should NOT gain IInputBackend — too many construction sites (`ISystemInfo.DesktopRectArea`, `new DesktopRegion()` everywhere) |
| No new static in Simulation | Simulation shim consumers migrate to their existing `_inputBackend` field, not to a new Simulation static setter |
| DesktopRegion source | Physical source is `BetterGenshinImpact/GameTask/Model/Area/DesktopRegion.cs`. Core links it. WPF compiles it as own source. WPF currently resolves PlatformServices symbol from the Core assembly reference. |

### 10.12 Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| DesktopRegion instance methods called from ~100+ WPF call sites via Region.ClickTo() | **High** — large migration surface | Parameterize methods with IInputBackend; WPF callers have their own IInputBackend from composition |
| Region.ClickTo() and Region.MoveTo() are deep in Region class hierarchy | **Medium** — changes propagate | Add IInputBackend parameter; Region doesn't own DesktopRegion instances but calls `ConvertRes<DesktopRegion>` which returns a DesktopRegion reference |
| Simulation facade migration requires updating GlobalMethod.cs (linked) | **Low** — single file, mechanical | Replace `Simulation.SendInput.Mouse.X()` with `_inputBackend.X()`; IInputBackend already available in scope |
| UnitTest `DesktopRegion(FakeMouseSimulator)` exists | **Low** — not in Core closure | UnitTest targets WPF, not Core; handled in WPF migration path |

### 10.13 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 112/112 ✅
```
