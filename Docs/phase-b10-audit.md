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
| History | Only commit `32590fc` creates this shim | No upstream, no predecessor |

There is no WPF tree `PlatformServices.cs`. The shim was written for the macOS port to satisfy `DesktopRegion`'s static reference to `PlatformServices.Input`.

**Source file note:** `DesktopRegion.cs` has its authoritative physical source at `BetterGenshinImpact/GameTask/Model/Area/DesktopRegion.cs`. Core compiles it through a linked `<Compile Include=... Link=...>` item. WPF compiles it as its own source file (default SDK glob). PlatformServices has no WPF authoritative definition — WPF currently resolves the public `PlatformServices` type from the referenced Core assembly.

### 10.3 Preprocessed reference table

Three-layer classification:

| Layer | PlatformServices.Input refs | Survives Core preprocessing? | Called from supported macOS path? |
|-------|---------------------------|------------------------------|-----------------------------------|
| **Textual references** | 7 (shim self 1, Simulation 1, DesktopRegion 5) | — | — |
| **Core-preprocessed symbol refs** | 6 (Simulation 1, DesktopRegion 5) | ✅ Yes | — |
| **Supported-runtime reachable calls** | 0 | — | ❌ No |

| # | File | Reference | Preprocessed in Core? | Runtime-reachable on macOS? |
|---|------|-----------|-----------------------|-----------------------------|
| 1 | `Shim/PlatformServices.cs` | Type definition | ✅ | N/A (definition) |
| 2 | `Shim/Simulation.cs` | `Simulation.InputBackend => PlatformServices.Input` | ✅ | ❌ No called from any Core-linked consumer |
| 3 | `DesktopRegion.cs:29` | `var input = PlatformServices.Input` | ✅ Method body compiled | ❌ Dead code on macOS |
| 4 | `DesktopRegion.cs:41` | `PlatformServices.Input.MoveMouseTo(...)` | ✅ | ❌ Dead code on macOS |
| 5 | `DesktopRegion.cs:48` | `var input = PlatformServices.Input` | ✅ | ❌ Dead code on macOS |
| 6 | `DesktopRegion.cs:58` | `PlatformServices.Input.MoveMouseTo(...)` | ✅ | ❌ Dead code on macOS |
| 7 | `DesktopRegion.cs:63` | `PlatformServices.Input.MoveMouseBy(...)` | ✅ | ❌ Dead code on macOS |
| 8 | `Region.cs:101` | `DesktopRegion.DesktopRegionMove(...)` via BackgroundClick | ✅ but inside `#if BGI_FULL_WINDOWS` | ❌ |
| 9 | `GameCaptureRegion.cs:97,105,113` | `DesktopRegion.DesktopRegionClick/Move/MoveBy` | ✅ but inside `#if BGI_FULL_WINDOWS` | ❌ |
| 10 | `Verification/Program.cs:22` | `PlatformServices.Input = recorder` | ✅ | Test-only write |
| 11 | `Verification/Program.cs:53,65` | `DesktopRegion.DesktopRegionMove(...)` | ✅ | Test-only |

**Correct statement:** Six Core-preprocessed symbol references survive compilation (items 2–7), but **zero supported-runtime code paths call them** on macOS.

#### 10.3.1 Preprocessor symbol check

```
BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj:
  <DefineConstants>$(DefineConstants);BGI_PLATFORM_MAC</DefineConstants>
  BGI_FULL_WINDOWS: NOT defined
BetterGenshinImpact/BetterGenshinImpact.csproj:
  BGI_FULL_WINDOWS: NOT defined
  BGI_PLATFORM_MAC: NOT defined
```

This means:
- `#if BGI_FULL_WINDOWS` blocks in GameCaptureRegion.cs and Region.cs are NEVER compiled (neither Core nor WPF)
- Only `BGI_PLATFORM_MAC` is defined — always, only in Core
- DesktopRegion.cs PlatformServices.Input refs have NO preprocessor guard — they are always compiled in both Core (linked) and WPF (authoritative)

### 10.4 Simulation trial deletion

Result from temporary deletion of `Shim/Simulation.cs` + its csproj entry:

| Check | Result |
|-------|--------|
| Core build | **0 errors** ✅ |
| Verification | **112/112** ✅ |
| WPF type-resolution | No new errors (Simulation type not exposed from Core public API) |
| Source guard: `\bSimulation\b` in Core/Verification | Zero production refs (definition only) |

**Simulation shim is a Category A candidate.** Its only connection to PlatformServices is `PlatformServices.Input` on line 10 — if PlatformServices is also removed, Simulation has no reason to exist.

### 10.5 PlatformServices-only deletion trial

Result from temporary deletion of `Shim/PlatformServices.cs` + its csproj entry:

| Error | File | Line | Message |
|-------|------|------|---------|
| CS0103 | `Shim/Simulation.cs` | 10 | `'PlatformServices' does not exist` |
| CS0103 | `DesktopRegion.cs` | 29,41,48,58,63 | `'PlatformServices' does not exist` |

**Conclusion:** PlatformServices cannot be deleted until all 6 compiled symbol references are resolved (5 in DesktopRegion, 1 in Simulation). Deleting PlatformServices also breaks WPF, because WPF's authoritative DesktopRegion.cs resolves the type from the Core assembly.

### 10.6 Architecture comparison for DesktopRegion/Region input methods

| Scheme | Core change | WPF change | Public API blast radius | Risk |
|--------|------------|------------|----------------------|------|
| **A — Parameterize with IInputBackend** | Add `IInputBackend input` param to DesktopRegionClick/Move/MoveBy and Region.ClickTo/MoveTo/Click/Move | Same API change propagates to all ~100 WPF callers via Region.ClickTo() | Very large — touches hundreds of call sites | High |
| **B — Guard with preprocessor** | Wrap DesktopRegion input methods in `#if BGI_PLATFORM_MAC` exclusivity. But `BGI_PLATFORM_MAC` is always defined in Core, never in WPF. WPF needs these methods. | WPF doesn't define any `BGI_*` symbol. | Requires adding a WPF-specific symbol or using negative condition | Medium — no existing symbol strategy |
| **C — Split geometry from input** | Move input methods to separate class; DesktopRegion stays geometry-only | Same refactor in WPF | Large — new type, all callers updated | High |
| **D — Keep PlatformServices** | No change to DesktopRegion/Region | No change | None | Low — temporary shim |

**Current B10 constraints favor Scheme D** — the smallest change. PlatformServices is a temporary shim (Category D) that will be removed in a later phase when a dedicated input-execution strategy for the shared Region hierarchy is established.

### 10.7 Category classification

| Shim | Classification | Rationale |
|------|---------------|-----------|
| **Simulation** | **Category A** — dead shim | Trial deletion passes: 0 errors, 112/112. Zero Core/Verification consumers. Can be deleted independently. |
| **PlatformServices** | **Category D/B** — temporary shim | Six compiled symbol references in DesktopRegion.cs/Simulation.cs prevent deletion. Runtime-reachable on macOS: zero. Exit condition: all six refs guarded or rewritten. |

### 10.8 Corrected implementation plan

#### B10.7.1: Delete Simulation shim only

- Delete `BetterGenshinImpact.Core/Shim/Simulation.cs` (79 lines — facades, SendInputFacade, KeyboardFacade, MouseFacade)
- Remove `<Compile Include="Shim/Simulation.cs" />` from Core csproj
- Core build: 0 errors ✅
- Verification: 112/112 ✅
- Shim count: 15 → **14**
- PlatformServices remains (Simulation was its only Core shim consumer; DesktopRegion still has 5 refs)

#### B10.7.2–4: *Future* — resolve PlatformServices compiled references

Postponed. Exit condition: all 5 DesktopRegion.cs `PlatformServices.Input` refs AND the 1 Simulation.cs ref (already removed in B10.7.1) are zero. Timeline: when a dedicated input-execution strategy for the shared Region/DesktopRegion hierarchy is established, or when the 5 methods are guarded/rewritten.

**This is NOT scheduled for immediate implementation.** PlatformServices stays Category D.

### 10.9 Verification strategy

| Current code | Status | Replacement |
|-------------|--------|-------------|
| `PlatformServices.Input = recorder;` | Core still exports PlatformServices (Category D — kept) | **Keep unchanged** until PlatformServices is removed |
| `DesktopRegion.DesktopRegionMove(960, 540)` | DesktopRegion input API still compiled in Core | **Keep unchanged** — tests DesktopRegion → PlatformServices → recorder chain |
| `DesktopRegion.DesktopRegionMove(1920, 1080)` | Same | **Keep unchanged** |
| `DesktopRegion.DisplayWidth = 1920` etc. | Geometry test, no PlatformServices dependency | **Keep unchanged** |

**No changes to verification during B10.7.** Verification continues using PlatformServices through the kept shim.

### 10.10 Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| WPF depends on Core assembly exporting `PlatformServices` | **Low** — PlatformServices is kept (Category D). This risk only materializes if PlatformServices is deleted before DesktopRegion refs are resolved. | Documented exit condition prevents premature deletion. |
| Simulation deletion removes `MouseFacade.LeftButtonClick()` etc. that might be expected by future Core-linked consumers | **Low** — zero current consumers. If needed in future, inject IInputBackend directly. | Document removal in commit message. |
| Verification test `PlatformServices.Input = recorder` is a static write | **Medium** — pattern violation but contained in test-only code. Acceptable for temporary shim. | Will be removed when PlatformServices reaches zero-reference state. |

### 10.11 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 112/112 ✅
```

### 10.12 B10.7.1 Implementation Result

| Metric | Before | After |
|--------|--------|-------|
| Core shim `Shim/Simulation.cs` | Exists (79 lines — Simulation, SendInputFacade, KeyboardFacade, MouseFacade) | **Deleted** ✅ |
| Core csproj entry | `<Compile Include="Shim/Simulation.cs" />` | **Removed** ✅ |
| Replacement static facade created? | — | **No** ✅ |
| Core production Simulation consumers | Zero | **Zero** ✅ |
| Verification Simulation consumers | Zero | **Zero** ✅ |
| WPF authoritative `Core/Simulator/Simulation.cs` | — | **Unchanged** ✅ |
| GlobalMethod.cs / ClickExtension.cs | Resolve WPF Simulation | **Unchanged** ✅ |
| AutoPickTrigger.cs Simulation comment | Comment only | **Unchanged** (comment still present) |
| PlatformServices kept | — | **Yes** ✅ (Category D) |
| PlatformServices compiled refs | 6 (Simulation 1 + DesktopRegion 5) | **5** (DesktopRegion 5 only) |
| Core build | 0 errors | **0 errors** ✅ |
| Core Verification | 112/112 | **112/112** ✅ |
| WPF build — new errors from Simulation deletion | — | **Zero** — same 4 pre-existing errors remain; no Simulation/namespace/type ambiguity errors added ✅ |
| Shim count | 15 | **14** ✅ |

**B10.7 status:** B10.7.1 complete. PlatformServices remains Category D. B10.7.2–4 postponed until a dedicated input-execution strategy for the shared Region/DesktopRegion hierarchy is established. No immediate work scheduled on PlatformServices.

---

## 11. B10.8 Audit: StringUtils

### 11.1 Current shim

| Aspect | Detail |
|--------|--------|
| File | `BetterGenshinImpact.Core/Shim/StringUtils.cs` |
| Lines | 8 |
| Namespace | `BetterGenshinImpact.Helpers` |
| Type kind | `public static class StringUtils` |
| Public API | 3 extension methods |

| Member | Signature | Implementation |
|--------|-----------|----------------|
| `IsNullOrEmpty` | `this string? s → bool` | `string.IsNullOrEmpty(s)` |
| `IsNotNullOrEmpty` | `this string? s → bool` | `!string.IsNullOrEmpty(s)` |
| `RemoveAllSpace` | `this string s → string` | `s.Replace(" ", "").Replace("\t", "").Replace("\n", "").Replace("\r", "")` |

Created in commit `32590fc` (macOS port). No predecessor, no WPF upstream analog.

### 11.2 Upstream/history investigation

| Aspect | WPF authoritative (`BetterGenshinImpact/Helpers/StringUtils.cs`) | Core shim |
|--------|----------------------------------------------------------------|-----------|
| Lines | 159 | 8 |
| Type keyword | `public partial class` | `public static class` |
| Extension methods? | **No** — all regular static | **Yes** — all `this string` extension |
| `IsNullOrEmpty` | **Not present** | ✅ Provided by shim |
| `IsNotNullOrEmpty` | **Not present** | ✅ Provided by shim |
| `RemoveAllSpace` | ✅ Removes ` ` + `\t` only (2 chars) | Removes ` ` + `\t` + `\n` + `\r` (4 chars — **different behavior**) |
| `RemoveAllEnter` | ✅ Removes `\n` + `\r` | ✅ But combined into RemoveAllSpace |
| `ExtractChinese`, `ConvertFullWidthNumToHalfWidth`, `TryParseInt`, `TryExtractPositiveInt`, `IsPureEnglish`, etc. | ✅ Full suite (11 methods total) | **Not present** |

**Key semantic difference:** The shim's `RemoveAllSpace` removes spaces, tabs, AND newlines. The WPF version only removes spaces and tabs (newlines are handled by separate `RemoveAllEnter`). This means Core consumers using the shim get more aggressive stripping than WPF consumers of the same-named method.

### 11.3 Three-layer reference classification

| Layer | Textual refs | Core-preprocessed | macOS runtime reachable |
|-------|-------------|-------------------|------------------------|
| `IsNullOrEmpty` | 0 | 0 | 0 |
| `IsNotNullOrEmpty` | 0 | 0 | 0 |
| `RemoveAllSpace` | 4 (ImageRegion 2, CraftMaterialTask 1 commented, AutoFishingTrigger 1 comment) | **2** (ImageRegion.cs:209,309) | ✅ Called from ImageRegion which is used in OCR processing path on macOS |

#### Consumer detail

| # | File | Project | Preprocessed? | Member | Runtime reachable on macOS? |
|---|------|---------|---------------|--------|----------------------------|
| 1 | `ImageRegion.cs:209` | Core (linked) | ✅ | `RemoveAllSpace(result.Text)` | ✅ Called from `ITaskTrigger.OnCapture` OCR processing |
| 2 | `ImageRegion.cs:309` | Core (linked) | ✅ | `RemoveAllSpace(result.Text)` | ✅ Called from `ImageRegion.Text()` OCR method |
| 3 | `AutoFishingTrigger.cs:186` | WPF | ❌ Comment only | `RemoveAllSpace` | Not code |
| 4 | `RectArea.cs:302` | WPF | ❌ Comment only | `RemoveAllSpace` | Not code |
| 5–15 | `CombatScenes.cs`, `Avatar.cs`, etc. | WPF | ❌ Not linked | Various members | WPF-only |

**Core consumers:** 2 calls to `RemoveAllSpace`, both in the macOS OCR processing path.

### 11.4 Trial deletion result

Temporary removal of shim + csproj entry:

| Error | File | Line | Message |
|-------|------|------|---------|
| CS0103 | `ImageRegion.cs` | 209 | `'StringUtils' does not exist in current context` |
| CS0103 | `ImageRegion.cs` | 309 | `'StringUtils' does not exist in current context` |

**Result:** Not directly deletable — 2 Core-compiled consumers exist. The shim is not dead.

### 11.5 Standard library replacement analysis

| Shim member | Standard equivalent | Replaceable? |
|-------------|-------------------|--------------|
| `IsNullOrEmpty(this string? s)` → `string.IsNullOrEmpty(s)` | `string.IsNullOrEmpty(s)` | ✅ Direct — just call `string.IsNullOrEmpty()` directly in consumer |
| `IsNotNullOrEmpty(this string? s)` → `!string.IsNullOrEmpty(s)` | `!string.IsNullOrEmpty(s)` | ✅ Direct — just call `!string.IsNullOrEmpty()` directly |
| `RemoveAllSpace(this string s)` → 4 `Replace` calls | `s.Replace(" ", "").Replace("\t", "").Replace("\n", "").Replace("\r", "")` | ⚠️ Equivalent to Core shim, **NOT** equivalent to WPF authoritative `RemoveAllSpace` |

**Critical shared-source constraint:** `BetterGenshinImpact/GameTask/Model/Area/ImageRegion.cs` is the WPF authoritative physical source. Core compiles it through a linked `<Compile Include=... Link=...>` item. This means **any unconditional change affects both targets**.

The two `RemoveAllSpace` implementations differ:

| Implementation | Removes space | Removes tab | Removes `\n` | Removes `\r` |
|----------------|:---:|:---:|:---:|:---:|
| Core shim `RemoveAllSpace` | ✅ | ✅ | ✅ | ✅ |
| WPF authoritative `RemoveAllSpace` | ✅ | ✅ | ❌ | ❌ |

If `StringUtils.RemoveAllSpace(result.Text)` is replaced with the 4-Replace expression unconditionally, WPF behavior changes (would start stripping newlines). This violates the "keep upstream WPF behavior" constraint.

### 11.6 Architecture classification

**Category B — Replace consumers with target-specific conditional, then delete shim.**

Not Category A — 2 Core-compiled consumers exist.
Not Category C — no shared utility logic to extract; standard APIs suffice.
Not Category D — shim is a thin wrapper, not a substantive implementation.
Not Category E — linking upstream adds `RegexHelper` dependency (used by `TryExtractPositiveInt` which Core doesn't need).

### 11.7 Neighboring shim relationship

| Shim | StringUtils reference? | Notes |
|------|-----------------------|-------|
| `App.cs` | No | Independent |
| `Global.cs` | No | Independent |
| `TaskControl.cs` | No | Independent |
| `ThemedMessageBox.cs` | No | Independent |
| `PlatformServices.cs` | No | Independent |
| `MacSystemInfo.cs` | No | Independent |

No ordering constraints. StringUtils is a utility leaf node with no inter-shim dependencies.

### 11.8 Implementation phases

#### B10.8.1: Add target-specific helper in ImageRegion.cs; replace 2 call sites

`ImageRegion.cs` is a shared physical source (authoritative in WPF, linked in Core). Add a private helper with `#if BGI_PLATFORM_MAC` to preserve both targets' semantics:

```csharp
private static string NormalizeOcrText(string text)
{
#if BGI_PLATFORM_MAC
    return text
        .Replace(" ", "")
        .Replace("\t", "")
        .Replace("\n", "")
        .Replace("\r", "");
#else
    return StringUtils.RemoveAllSpace(text);
#endif
}
```

Replace both call sites (lines 209, 309):

```csharp
// Before:
var text = StringUtils.RemoveAllSpace(result.Text);
// After:
var text = NormalizeOcrText(result.Text);
```

**Behavior preservation:**

| Target | Before | After | Delta |
|--------|--------|-------|-------|
| Core (BGI_PLATFORM_MAC) | shim: 4-char removal | NormalizeOcrText: 4-char removal | ✅ Identical |
| WPF (no BGI_PLATFORM_MAC) | authoritative StringUtils.RemoveAllSpace: 2-char removal | NormalizeOcrText → StringUtils.RemoveAllSpace: 2-char removal | ✅ Identical |

**After this step:** `rg '\bStringUtils\b' BetterGenshinImpact.Core/ --type cs` → zero production code hits (comment-only). Core preprocessing no longer requires the StringUtils type.

#### B10.8.2: Delete StringUtils shim + csproj entry

- Delete `BetterGenshinImpact.Core/Shim/StringUtils.cs`
- Remove `<Compile Include="Shim/StringUtils.cs" />` from Core csproj
- Core build 0 errors (after B10.8.1, `BGI_PLATFORM_MAC` preprocessing removes the `#else` branch, so `StringUtils` is not needed)
- Verification 112/112
- WPF: ImageRegion's `#else` branch continues resolving WPF authoritative `StringUtils` — no build change
- Shim count: 14 → **13**

**Core build gate (B10.8.2):** `dotnet build BetterGenshinImpact.Core.csproj` succeeds — the `#else` branch is removed by `BGI_PLATFORM_MAC` preprocessing, so `StringUtils` is not required at compile time.

**WPF check (B10.8.2):** `ImageRegion.cs` `#else` branch continues resolving `BetterGenshinImpact.Helpers.StringUtils` (WPF authoritative source). No change to WPF newline-stripping semantics.

**Source guard note:** Textual `StringUtils` references remain in `ImageRegion.cs` (inside `#else`), but they are preprocessed out of Core. `rg` should check Core-preprocessed closure, not raw physical text.

### 11.9 Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Unconditional inline would change WPF newline-stripping behavior | **High** — prevented by `#if BGI_PLATFORM_MAC` conditional in NormalizeOcrText | ✅ Conditional ensures both targets see their expected semantics |
| `NormalizeOcrText` is a private helper — not reusable outside ImageRegion | **Low** — intentional; only 2 call sites exist, both in ImageRegion | No action needed |
| WPF `StringUtils` partial class keyword may cause confusion if another partial exists | **Low** — only one WPF file uses `partial`; no other partial found | No action needed |
| TryExtractPositiveInt references RegexHelper — prevents linking upstream StringUtils into Core | **Low** — we chose conditional inline, not linking | Correct by design |

### 11.11 B10.8 Implementation Result

| Metric | Before | After |
|--------|--------|-------|
| `NormalizeOcrText` helper | — | Added as `private static` in ImageRegion with `#if BGI_PLATFORM_MAC` ✅ |
| ImageRegion line 209 call | `StringUtils.RemoveAllSpace(result.Text)` | `NormalizeOcrText(result.Text)` ✅ |
| ImageRegion line 309 call | `StringUtils.RemoveAllSpace(result.Text)` | `NormalizeOcrText(result.Text)` ✅ |
| Core behavior (`BGI_PLATFORM_MAC` branch) | shim: 4-char removal | 4 explicit `Replace` calls — same ✅ |
| WPF behavior (`#else` branch) | authoritative `StringUtils.RemoveAllSpace`: 2-char removal | Same — calls into authoritative source ✅ |
| WPF authoritative `StringUtils.cs` | — | **Unchanged** ✅ |
| Core shim `Shim/StringUtils.cs` | Exists (8 lines) | **Deleted** ✅ |
| Core csproj entry | `<Compile Include="Shim/StringUtils.cs" />` | **Removed** ✅ |
| Unused extension methods | `IsNullOrEmpty`, `IsNotNullOrEmpty` | Removed with shim (zero consumers) ✅ |
| Core-preprocessed StringUtils dependency | 2 refs (via shim) | **Zero** (textual `#else` ref preprocessed out) ✅ |
| Core build | 0 errors | **0 errors** ✅ |
| Core Verification | 112/112 | **112/112** ✅ |
| WPF build — new errors from this change | — | **Zero** — only same 4 pre-existing errors remain ✅ |
| Shim count | 14 | **13** ✅ |
| B10.8 status | — | **Complete** ✅ |

---

## 12. B10.9 Audit: TaskControl

### 12.1 Current shim

| Aspect | Detail |
|--------|--------|
| File | `BetterGenshinImpact.Core/Shim/TaskControl.cs` |
| Lines | 11 |
| Namespace | `BetterGenshinImpact.GameTask` |
| Type kind | `public static class TaskControl` |
| Created | Commit `32590fc` (macOS port) |

| Member | Signature | Implementation | Nature |
|--------|-----------|----------------|--------|
| `Logger` | `static ILogger Logger { get; }` | `NullLogger.Instance` | Silent no-op logger |
| `CaptureToRectArea()` | `static ImageRegion()` | `new ImageRegion(new Mat(), 0, 0)` | Empty Mat placeholder — zero pixels, zero channels effectively |
| `Sleep(int)` | `static void Sleep(int ms)` | `Thread.Sleep(ms)` | Standard blocking sleep |

### 12.2 Upstream/history investigation

| Aspect | WPF authoritative (`GameTask/Common/TaskControl.cs`) | Core shim |
|--------|------------------------------------------------------|-----------|
| Lines | 313 | 11 |
| Type keyword | `class` (instance + static members) | `static class` |
| `Logger` | `App.GetLogger<TaskControl>()` — real ILogger from DI | `NullLogger.Instance` — silent |
| `CaptureToRectArea()` | Real capture via `IGameCapture` pipeline | `new ImageRegion(new Mat(), 0, 0)` — empty placeholder |
| `Sleep(int)` | `TrySuspend()` + `CheckAndActivateGameWindow()` + `Thread.Sleep` | `Thread.Sleep` only — no suspend/window activation |
| Other members (not in shim) | `TaskSemaphore`, `CheckAndSleep`, `Delay`, `TrySuspend`, `CheckAndActivateGameWindow`, `CaptureGameImage`, `NewRetry`, etc. | **Not present** |

Only commit `32590fc` creates the shim. No prior history.

### 12.3 Reference classification (three layers)

#### 12.3.1 Pre-coreprocessing textual references

| Member | Textual refs | Core-preprocessed | Supported-runtime reachable |
|--------|-------------|-------------------|---------------------------|
| `Logger` | ~40 (WPF) + 1 (Core-linked) | **1** (ImageRegion.cs:163) | ✅ — ImageRegion.Find() calls Logger on error |
| `CaptureToRectArea()` | ~30 (WPF) | **0** | ❌ — Only in WPF-linked (HotKeyViewModel, QuickBuyTask, etc.) |
| `Sleep(int)` | ~15 (WPF) + 1 (Core-linked) | **1** (Region.cs:120) | ✅ — Region.Click() calls Sleep(60) |

#### 12.3.2 Core-compiled consumers

| # | File | Line | Member | Preprocessed? | macOS reachable? |
|---|------|------|--------|---------------|------------------|
| 1 | `ImageRegion.cs` (linked) | 163 | `TaskControl.Logger.LogError(...)` | ✅ Compiled | ✅ OCR error path in `Find()` |
| 2 | `Region.cs` (linked) | 120 | `TaskControl.Sleep(60)` | ✅ Compiled | ✅ `Region.Click()` → `DoubleClick()` path |

**Note:** Both files are shared sources (authoritative in WPF tree, linked in Core). Unconditional changes affect both targets.

#### 12.3.3 Verification references

**Zero.** Verification does not reference TaskControl.

#### 12.3.4 WPF-only refs (not compiled in Core)

~70+ refs across WPF using various TaskControl members. Not in scope.

### 12.4 Individual member analysis

#### 12.4.1 TaskControl.Logger (ImageRegion.cs:163)

```csharp
TaskControl.Logger.LogError("在图像{W1}x{H1}中查找模板...");
```

Called when a template match's region-of-interest exceeds the source image boundaries. This is an edge-case error log in `ImageRegion.Find()`. The caller already has no other logger available — ImageRegion is a model class without DI injection.

**Shim value:** `NullLogger.Instance` — message is silently discarded on macOS.
**Upstream value:** Real DI-resolved ILogger — message appears in log.

**Classification:** Category D/B — keep temporarily. Logger injection into ImageRegion would be a large refactor (shared source, impacts all region types). The `NullLogger` behavior means macOS loses diagnostic info, but doesn't crash or misbehave.

#### 12.4.2 TaskControl.CaptureToRectArea() (no Core consumers)

Zero Core-preprocessed consumers. Only WPF files call this member. The shim's implementation (empty Mat placeholder) is never invoked from Core.

**Classification:** Category A — dead member in Core. But it cannot be removed from the shim because the shim must provide the type for WPF compilation... Wait — WPF has its own authoritative TaskControl. WPF doesn't use the shim.

Actually, WPF resolves its own `GameTask/Common/TaskControl.cs`. The Core shim is only compiled in Core. So this member has zero consumers in both targets' closures. It can be removed from the shim without affecting anything.

**Classification:** Category A — dead member in the shim. Remove it from the shim.

#### 12.4.3 TaskControl.Sleep(int) (Region.cs:120)

```csharp
TaskControl.Sleep(60);
```

Called in `Region.DoubleClick()` which calls `ClickTo()` then sleeps, then `ClickTo()` again. On macOS, this is dead code — no Core-linked consumer calls `Region.DoubleClick()` (confirmed in B10.7 audit). However, the method body is compiled and would be called if any trigger calls `DoubleClick()` in the future.

Wait — `Region.DoubleClick()` calls `TaskControl.Sleep(60)` directly. If no Core-linked code calls `DoubleClick()`, then the `Sleep` call is unreachable at runtime but exists in compiled code.

**Shim value:** `Thread.Sleep(ms)` — blocking sleep, no cancellation.
**Upstream value:** `TrySuspend()` + `CheckAndActivateGameWindow()` + `Thread.Sleep(ms)` — includes platform window management.

**Classification:** Category D/B — keep temporarily. The Sleep reference is in shared Region.cs. Adding `#if` guard or replacing with `Thread.Sleep` inline would be needed to remove the shim dependency.

### 12.5 Trial deletion result

Removing shim + csproj entry:

| Error | File | Line | Message |
|-------|------|------|---------|
| CS0103 | `Region.cs` | 120 | `'TaskControl' does not exist` |
| CS0103 | `ImageRegion.cs` | 163 | `'TaskControl' does not exist` |

**2 compiled symbol references prevent deletion.** Both in shared source files.

### 12.6 Per-member classification

| Member | Classification | Rationale |
|--------|---------------|-----------|
| `Logger` | **Category D** — keep temporarily. Replace with injected ILogger when ImageRegion gets DI support. | Single log call, edge case. NullLogger silences it on macOS (acceptable for B10). |
| `CaptureToRectArea()` | **Category A** — dead member in shim. Zero consumers in Core closure. | Remove from shim immediately. |
| `Sleep(int)` | **Category D** — keep temporarily. Remove when Region.DoubleClick() consumer pattern is clarified in Core. | Shared source, single call, dead on supported path. |

### 12.7 Neighboring shim relationship

| Shim | TaskControl ref? | Notes |
|------|------------------|-------|
| `App.cs` | No | Independent |
| `Global.cs` | No | Independent |
| `PlatformServices.cs` | No | Independent |
| `MacSystemInfo.cs` | No | Independent |
| `ThemedMessageBox.cs` | No | Independent |

No ordering constraints.

### 12.8 Implementation phases

#### B10.9.1: Remove dead `CaptureToRectArea()` from shim

Delete the method and its `using OpenCvSharp;` (if it becomes unused). Zero consumers confirmed.

**Gate:** Core build 0 errors, Verification 112/112.

#### B10.9.2: Guard or replace `TaskControl.Sleep` in Region.cs

Two options:
- **A (recommended):** Replace `TaskControl.Sleep(60)` with `Thread.Sleep(60)` directly, then add `using System.Threading;` if needed.
- **B:** Guard with `#if BGI_PLATFORM_MAC` exclusive inline `Thread.Sleep`, keep `#else` branch calling `TaskControl.Sleep`.

Both preserve behavior since the shim's `Sleep` is just `Thread.Sleep`. Option A is simpler.

**Gate:** Core build 0 errors, Verification 112/112. WPF: `#else` branch or unconditional change must be evaluated for shared-source impact.

#### B10.9.3: Guard or replace `TaskControl.Logger` in ImageRegion.cs

Replace `TaskControl.Logger.LogError(...)` with `#if BGI_PLATFORM_MAC` that skips logging (or uses a local `NullLogger` instance), or replaces with a standard `ILogger` if available.

Since ImageRegion has no DI, the simplest option is:
```csharp
#if !BGI_PLATFORM_MAC
TaskControl.Logger.LogError(...);
#endif
```

This removes the dependency from Core while preserving WPF diagnostic logging.

**Gate:** Core build 0 errors, Verification 112/112.

#### B10.9.4: Delete TaskControl shim

After B10.9.1–3, Core-preprocessed references to TaskControl are zero:
- Delete `BetterGenshinImpact.Core/Shim/TaskControl.cs`
- Remove csproj entry
- Core build 0 errors
- Verification 112/112
- Shim count: 13 → **12**

### 12.9 Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| `CaptureToRectArea()` removal from shim won't affect WPF | **None** — WPF has its own authoritative implementation | Not a risk |
| `Region.cs` shared source — replacing `TaskControl.Sleep` with `Thread.Sleep` is same behavior on both targets | **Low** — identical semantics (both just call `Thread.Sleep`) | Verified by code inspection |
| Losing `Logger.LogError` on macOS reduces diagnostic visibility | **Low** — edge case log, no behavioral impact | Acceptable for B10 phase |
| ImageRegion.cs and Region.cs are shared sources — all changes affect both | **Medium** — verify WPF behavior is preserved (use `#if` when semantics diverge) | Test plan covers both |

### 12.10 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 112/112 ✅
```

### 12.11 B10.9.1 Implementation Result

| Metric | Before | After |
|--------|--------|-------|
| `TaskControl.CaptureToRectArea()` in shim | Present (empty Mat placeholder) | **Removed** ✅ |
| Core consumers of `CaptureToRectArea()` | Zero | **Zero** ✅ |
| Verification consumers | Zero | **Zero** ✅ |
| WPF authoritative `CaptureToRectArea()` | — | **Unchanged** ✅ |
| Core build | 0 errors | **0 errors** ✅ |
| Core Verification | 112/112 | **112/112** ✅ |
| Logger / Sleep in shim | Retained | **Retained** (Category D) ✅ |
| Shim count | 13 | **12** ✅ |
| B10.9.1 status | — | **Complete** ✅ |

### 12.12 B10.9.2 Implementation Result

| Metric | Before | After |
|--------|--------|-------|
| `TaskControl.Sleep` ref in Region.cs | Unconditional `TaskControl.Sleep(60)` | `#if BGI_PLATFORM_MAC` → `Thread.Sleep(60)` / `#else` → `TaskControl.Sleep(60)` ✅ |
| Core behavior (`BGI_PLATFORM_MAC` branch) | Via shim: `Thread.Sleep(60)` | Direct `Thread.Sleep(60)` — same ✅ |
| WPF behavior (`#else` branch) | Via authoritative: suspend+activate+Thread.Sleep | Same — continues using `TaskControl.Sleep(60)` ✅ |
| Remaining TaskControl refs in Core closure | 2 (Sleep + Logger) | **1** (Logger only) ✅ |
| Core build | 0 errors | **0 errors** ✅ |
| Core Verification | 112/112 | **112/112** ✅ |
| WPF build — new errors | — | **Zero** (same 4 pre-existing) ✅ |
| Shim count | 12 | **12** (unchanged) ✅ |
| B10.9.2 status | — | **Complete** ✅ |
| Remaining TaskControl shim members | `Logger` (Category D) | **Unchanged** ✅ |

### 12.13 B10.9.3 Audit: TaskControl.Logger

#### 12.13.1 Current state

Only one Core-preprocessed consumer remains in `ImageRegion.cs:163`:

```csharp
TaskControl.Logger.LogError("在图像{W1}x{H1}中查找模板,名称：{Name},ROI位置{X2}x{Y2},区域{H2}x{W2},边界溢出！",
    roi.Width, roi.Height, ro.Name, ro.RegionOfInterest.X, ro.RegionOfInterest.Y,
    ro.RegionOfInterest.Width, ro.RegionOfInterest.Height);
```

| Attribute | Value |
|-----------|-------|
| Consumer file | `BetterGenshinImpact/GameTask/Model/Area/ImageRegion.cs` |
| Source ownership | Authoritative WPF source, linked in Core |
| Method | `ImageRegion.Find()` — template match with ROI bounds check |
| Triggered when | ROI exceeds source image dimensions (edge case) |
| Core shim provides | `NullLogger.Instance` — message silently discarded |
| WPF authoritative provides | `App.GetLogger<TaskControl>()` — real DI ILogger |
| Verification | Zero references |

#### 12.13.2 Consumer analysis

| Check | Answer |
|-------|--------|
| Does ImageRegion already have an ILogger? | **No** — ImageRegion is a model class with no DI |
| Is call inside `#if` block? | **No** — unconditional |
| Is call reachable from AutoPickTrigger? | ✅ Yes — `Find()` is called in OCR processing path, but the ROI-bounds error is an edge case |
| Would silencing the log cause behavioral issues? | **No** — it's a diagnostic message only |
| Is there an alternative ILogger available from the call chain? | `AutoPickTrigger` has `ILogger<AutoPickTrigger>` via `App.GetLogger`, but ImageRegion doesn't receive it |
| WPF-only approach possible? | Partially — ImageRegion is shared source, so a `#if` would be needed |

#### 12.13.3 Options

**A — Guard with `#if !BGI_PLATFORM_MAC` (recommended):**
```csharp
#if !BGI_PLATFORM_MAC
TaskControl.Logger.LogError("在图像{W1}x{H1}中查找模板...", ...);
#endif
```
- Core: removes the log (no diagnostic, no crash)
- WPF: unchanged — continues using authoritative TaskControl.Logger
- Risk: lowest

**B — Inject ILogger into ImageRegion constructor:**
- Requires adding `ILogger` parameter to ImageRegion
- Propagates to all Region subclasses (GameCaptureRegion, DesktopRegion, etc.)
- Risk: highest — large API change, shared source impact

**C — Use a local static NullLogger instance:**
```csharp
private static readonly ILogger _log = NullLogger.Instance;
```
- Core: uses NullLogger explicitly (no TaskControl dependency)
- WPF: still NullLogger — loses real DI logging
- Risk: WPF diagnostic regression

**D — Keep current shim (Category D):**
- No change
- Risk: lowest, but prolongs shim lifetime

**Recommendation: Option A** — matches the `#if BGI_PLATFORM_MAC` pattern used for StringUtils and Sleep. Minimal change, preserves both target behaviors.

#### 12.13.4 Implementation plan (B10.9.4 — combined with shim deletion)

After the `#if !BGI_PLATFORM_MAC` guard is applied:
- Core-preprocessed `TaskControl` refs: **zero**
- Delete `BetterGenshinImpact.Core/Shim/TaskControl.cs`
- Remove csproj entry
- Core build 0 errors
- Verification 112/112
- WPF: Logger code via `#else` branch — unchanged
- Shim count: 12 → **11**

#### 12.13.5 Risk

| Risk | Severity | Mitigation |
|------|----------|------------|
| Losing diagnostic log on macOS reduces debuggability | **Low** — edge case error that doesn't affect core behavior | Acceptable for B10 phase; can be addressed by full DI injection later |
| WPF behavior unaffected | ✅ Verifiable by inspection — `#if !BGI_PLATFORM_MAC` ensures WPF continues using authoritative TaskControl.Logger | Not a risk |

### 12.14 B10.9.4 Implementation Result

| Metric | Before | After |
|--------|--------|-------|
| `ImageRegion.cs` Logger call | Unconditional `TaskControl.Logger.LogError(...)` | Guarded with `#if !BGI_PLATFORM_MAC` ✅ |
| Core behavior | NullLogger — silent discard | Removed via `#if` — no TaskControl dependency ✅ |
| WPF behavior | Authoritative `TaskControl.Logger.LogError(...)` | Same — `#else` preserves original ✅ |
| Core shim `Shim/TaskControl.cs` | Exists (11 lines → 8 → removed CaptureToRectArea → removed) | **Deleted** ✅ |
| Core csproj entry | `<Compile Include="Shim/TaskControl.cs" />` | **Removed** ✅ |
| Core-preprocessed TaskControl refs | 2 (Sleep + Logger) → 1 (Logger only) | **Zero** ✅ |
| WPF authoritative `TaskControl.cs` | — | **Unchanged** ✅ |
| Core build | 0 errors | **0 errors** ✅ |
| Core Verification | 112/112 | **112/112** ✅ |
| WPF build — new errors | — | **Zero** (same 4 pre-existing) ✅ |
| Shim count | 12 | **11** ✅ |
| TaskControl chain status | CaptureToRectArea deleted, Sleep migrated, Logger guarded | **Complete** ✅ |

---

## 13. B10.10 Audit: ThemedMessageBox

### 13.1 Current shim

| Aspect | Detail |
|--------|--------|
| File | `BetterGenshinImpact.Core/Shim/ThemedMessageBox.cs` |
| Lines | 21 |
| Namespace | `BetterGenshinImpact.View.Windows` |
| Type kind | `public static class ThemedMessageBox` |
| Members | `IUserInteractionService? UserInteraction { get; set; }` (mutable static, nullable), `Error(string)`, `Warning(string)` |
| Mechanism | `UserInteraction?.ShowError(message)` — null-safe no-op when UserInteraction is null |
| WPF authoritative type | `BetterGenshinImpact/View/Windows/ThemedMessageBox.xaml.cs` — `partial class ThemedMessageBox : FluentWindow` (full WPF UI window) |
| Origin | Created in commit `32590fc` (macOS port) |

### 13.2 Reference classification

| Layer | References | Notes |
|-------|-----------|-------|
| Textual refs | ~50 across WPF + 3 in Core-linked files | |
| Core-preprocessed | **3** — all in `AutoPickTrigger.cs` (linked) | `ThemedMessageBox.Error(...)` in ReadJson/ReadText helpers |
| Supported-runtime reachable | **3** — called when pick list files fail to load (error dialogs) | On macOS, the null-conditional operator silently no-ops |
| Verification | **Zero** | |

### 13.3 Consumer detail

| # | File | Line | Call | macOS effect |
|---|------|------|------|-------------|
| 1 | `AutoPickTrigger.cs` | 131 | `ThemedMessageBox.Error("读取拾取黑/白名单失败...")` | No-op (`UserInteraction` is null) |
| 2 | `AutoPickTrigger.cs` | 151 | `ThemedMessageBox.Error("读取拾取黑/白名单失败...")` | No-op |
| 3 | `AutoPickTrigger.cs` | 171 | `ThemedMessageBox.Error("读取拾取黑/白名单失败...")` | No-op |

All 3 calls are in `catch` blocks for JSON/text file loading failures. The shim's null-safe `?.ShowError()` is already safe — no crashes, no behavioral impact.

### 13.4 Architecture classification

| Check | Answer |
|-------|--------|
| Static gateway? | **Yes** — `UserInteraction` is a mutable static property |
| Null!/no-op default? | **Yes** — null default means silent no-op on macOS |
| Core consumers with runtime reachability? | **3** — error dialogs, safe no-op |
| Verification refs? | Zero |
| WPF authoritative type? | `ThemedMessageBox : FluentWindow` — full WPF window, not shared source |
| Can shim be deleted? | Not until AutoPickTrigger's 3 `ThemedMessageBox.Error()` calls are removed or guarded |

**Category D/B temporary shim.** Three compiled consumers prevent deletion. The null-safe `?.ShowError()` pattern means the shim is already safe — it just silently drops UI dialogs on macOS.

### 13.5 Options

**A — Guard AutoPickTrigger.Error calls with `#if !BGI_PLATFORM_MAC`:**
- Removes the 3 Error dialog calls from Core
- WPF continues using authoritative ThemedMessageBox
- Risk: macOS loses diagnostic popups on file loading failures (already getting no-op)
- Needs `using BetterGenshinImpact.View.Windows` guarded or conditional

**B — Replace with logger:**
- `ThemedMessageBox.Error(...)` → `_logger.LogError(...)`
- AutoPickTrigger already has `ILogger<AutoPickTrigger>` at line 27
- Risk: lowest — replaces UI popup with log message, better than silent no-op

**C — Keep temporarily (Category D):**
- No change
- Shim already null-safe, no crash risk

**Recommendation: Option B** — AutoPickTrigger already has `_logger`. Replace the 3 `ThemedMessageBox.Error(...)` calls with `_logger.LogError(...)`.
- Core: gets structured log instead of silent no-op (improvement)
- WPF: loses UI popup, gets structured log (acceptable — callers already log the exception)
- Risk: lowest — no new dependency, no shared source issue (AutoPickTrigger is Core-linked)

### 13.6 Minimal implementation plan

#### B10.10.1: Replace ThemedMessageBox.Error calls in AutoPickTrigger

3 call sites, all in `catch` blocks:

```csharp
// Before:
ThemedMessageBox.Error("读取拾取黑/白名单失败...");
// After:
_logger.LogError("读取拾取黑/白名单失败: {Path}", jsonFilePath);
```

Same for both ReadJson and ReadText variants. AutoPickTrigger already has `_logger` at line 27.

#### B10.10.2: Delete ThemedMessageBox shim

After B10.10.1:
- Delete `BetterGenshinImpact.Core/Shim/ThemedMessageBox.cs`
- Remove csproj entry
- Core build 0 errors
- Verification 112/112
- Shim count: 11 → **10**

### 13.7 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 112/112 ✅
```

### 13.8 B10.10.1 Implementation Result

| Metric | Before | After |
|--------|--------|-------|
| `ThemedMessageBox.Error(...)` in AutoPickTrigger | 3 calls (lines 131, 151, 171) | **Removed** ✅ |
| Replacement | — | Existing `_logger.LogError(e, ...)` at same lines ✅ |
| `using BetterGenshinImpact.View.Windows` in AutoPickTrigger | Present | **Removed** (unused) ✅ |
| Core shim `Shim/ThemedMessageBox.cs` | Exists (21 lines) | **Deleted** ✅ |
| Core csproj entry | `<Compile Include="Shim/ThemedMessageBox.cs" />` | **Removed** ✅ |
| Core-preprocessed ThemedMessageBox refs | 3 | **Zero** ✅ |
| Verification refs | Zero | **Zero** ✅ |
| WPF authoritative `ThemedMessageBox : FluentWindow` | — | **Unchanged** ✅ |
| Core build | 0 errors | **0 errors** ✅ |
| Core Verification | 112/112 | **112/112** ✅ |
| Shim count | 11 | **10** ✅ |

---

## 14. B10.11 Audit: BvStubs

### 14.1 Current shim

| Aspect | Detail |
|--------|--------|
| File | `BetterGenshinImpact.Core/Shim/BvStubs.cs` |
| Lines | 13 |
| Namespace | `BetterGenshinImpact.GameTask.Common.BgiVision` |
| Type kind | `public static class Bv` |

| Member | Signature | Implementation | Type |
|--------|-----------|----------------|------|
| `WhichGameUi(ImageRegion)` | `→ GameUiCategory` | `=> GameUiCategory.Unknown` | Stub — always Unknown |
| `WhichGameUi()` | `→ GameUiCategory` | `=> GameUiCategory.Unknown` | Stub — always Unknown |
| `WhichGameUiForTriggers(ImageRegion)` | `→ GameUiCategory` | `=> GameUiCategory.Unknown` | Stub — always Unknown |
| `DetectChatUi(ImageRegion)` | `→ bool` | `=> false` | Stub — always false |
| `ImRead(string, ImreadModes)` | `→ Mat` | `=> Cv2.ImRead(path, mode)` | Real passthrough |

### 14.2 Upstream/history

WPF authoritative: `BetterGenshinImpact/GameTask/Common/BgiVision/` contains 6 `partial class Bv` files:
- `BvImage.cs`, `BvSkill.cs`, `BvOcr.cs`, `BvChatUi.cs`, `BvStatus.cs`, `BvSimpleOperation.cs`

Core shim provides only 5 members vs. WPF's ~30+. Created in commit `32590fc`.

### 14.3 Reference classification

| Member | Core-preprocessed refs | WPF-only refs | Verification refs | macOS reachable? |
|--------|----------------------|---------------|-------------------|------------------|
| `WhichGameUi` | **0** | Many | 0 | ❌ |
| `WhichGameUiForTriggers` | **0** | Many | 0 | ❌ |
| `DetectChatUi` | **0** | Many | 0 | ❌ |
| `ImRead` | **1** (`PaddleOcrService.cs:256`) | Many | 0 | ✅ Pre-heat OCR loading |

**Total Core-preprocessed references: 1** — `Bv.ImRead(...)` in `PaddleOcrService.cs`.

### 14.4 Semantic comparison: Bv.ImRead

| Implementation | Code | Encoding fallback | File I/O |
|----------------|------|-------------------|----------|
| Core shim | `Cv2.ImRead(path, mode)` | OpenCV internal | OpenCV native |
| WPF authoritative | `Mat.FromStream(File.OpenRead(fileName), flags)` | .NET → OpenCV | .NET FileStream |

### 14.5 Trial deletion result

| Error | File | Line | Message |
|-------|------|------|---------|
| CS0103 | `PaddleOcrService.cs` | 256 | `'Bv' does not exist in current context` |

**1 compiled symbol reference prevents deletion.**

### 14.6 Per-member classification

| Member | Classification | Rationale |
|--------|---------------|-----------|
| `WhichGameUi` | **A** — dead member | Zero Core consumers |
| `WhichGameUiForTriggers` | **A** — dead member | Zero Core consumers |
| `DetectChatUi` | **A** — dead member | Zero Core consumers |
| `ImRead` | **D** — keep temporarily | 1 Core consumer in linked PaddleOcrService.cs |

### 14.7 Options for Bv.ImRead

PaddleOcrService.cs is a linked shared source (authoritative in WPF tree, linked in Core). The shim `Cv2.ImRead` and WPF authoritative `Mat.FromStream(File.OpenRead(...))` have different implementations.

**A — Guard with `#if BGI_PLATFORM_MAC`:**
```csharp
#if BGI_PLATFORM_MAC
using var preHeatImageMat = Cv2.ImRead(modelType.PreHeatImagePath);
#else
using var preHeatImageMat = Bv.ImRead(modelType.PreHeatImagePath);
#endif
```
- Core: uses `Cv2.ImRead` (same as current shim)
- WPF: continues using `Bv.ImRead` (authoritative implementation)
- Risk: low, matches established pattern

**B — Keep shim temporarily (Category D):**
- No change, shim stays
- Risk: lowest

**C — Replace unconditionally with `Cv2.ImRead`:**
- Changes WPF behavior from `Mat.FromStream` to `Cv2.ImRead`
- Risk: unnecessary WPF behavior change

**Recommendation: Option A.** The `#if BGI_PLATFORM_MAC` pattern has been proven for StringUtils, Sleep, and Logger.

### 14.8 Implementation plan

#### B14.8.1: Guard Bv.ImRead in PaddleOcrService.cs

Replace `Bv.ImRead(...)` with `#if BGI_PLATFORM_MAC` / `Cv2.ImRead(...)` / `#else Bv.ImRead(...)`.

Remove 4 dead members from shim (WhichGameUi × 2, WhichGameUiForTriggers, DetectChatUi) — they have zero Core consumers and can be deleted without any migration.

#### B14.8.2: Delete BvStubs shim

After B14.8.1:
- Delete `BetterGenshinImpact.Core/Shim/BvStubs.cs`
- Remove csproj entry
- Core build 0 errors, Verification 112/112
- Shim count: 10 → **9**

### 14.9 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 112/112 ✅
```
