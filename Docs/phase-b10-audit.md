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

### 8.10 Baseline

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 112/112
```

No code modified during this audit.
