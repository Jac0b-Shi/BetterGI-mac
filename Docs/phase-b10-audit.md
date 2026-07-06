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

### 7.1 Current shim

| Aspect | Detail |
|--------|--------|
| File | `BetterGenshinImpact.Core/Shim/SpeedTimer.cs` |
| Namespace | `BetterGenshinImpact.Helpers` |
| API | `Record(string name)`, `DebugPrint()`, internal `Stopwatch` + `Dictionary<string, long>` |
| Dependencies | `System.Diagnostics` (Stopwatch) — pure C#, no WPF/Win32/ServiceProvider |
| Comment | "Linked from upstream (pure C#, no Windows deps)" — but no upstream copy exists |

### 7.2 Consumers

| Consumer | Core-linked? | Usage | Business impact if removed |
|----------|-------------|-------|---------------------------|
| `AutoPickTrigger.OnCapture` | ✅ Yes | 7 calls: `new SpeedTimer()` + 6 `Record()` + `DebugPrint()` | **None** — debug timing only, `DebugPrint()` is a no-op |
| `Feature2DExtensions.cs` | ❌ WPF-only | 3 `SpeedTimer()` | None — debug only |
| `AutoFight/CombatScenes.cs` | ❌ WPF-only | 1 `SpeedTimer()` | None |
| `TaskTriggerDispatcher.cs` | ❌ WPF-only | 1 `SpeedTimer()` | None |
| `Common/Map/*.cs` | ❌ WPF-only | 4 `SpeedTimer()` | None |
| `Test/*` | ❌ Test project | 5 `SpeedTimer()` | None — tests |

**Only consumer in Core-linked files:** `AutoPickTrigger.OnCapture` — debug performance logging, no business impact.

### 7.3 Upstream comparison

No authoritative upstream `Helpers/SpeedTimer.cs` exists. The shim is the only implementation and is pure C# (Stopwatch + Dictionary + Console). It can serve as the authoritative shared source.

### 7.4 Conclusion

**Category B — can be replaced with authoritative shared linked source** (same pattern as BgiKeyMapper).

The shim is pure C#, no WPF/Win32/ServiceProvider dependencies. Move to `BetterGenshinImpact/Helpers/SpeedTimer.cs`, link from Core csproj, delete Shim copy.

### 7.5 Implementation plan

1. Move `Shim/SpeedTimer.cs` → `BetterGenshinImpact/Helpers/SpeedTimer.cs`
2. Core csproj: delete `<Compile Include="Shim/SpeedTimer.cs" />`, add `<Compile Include="../BetterGenshinImpact/Helpers/SpeedTimer.cs" Link="Helpers/SpeedTimer.cs" />`
3. Verify: Core build zero errors, Verification unchanged
4. WPF: auto-compiled via SDK glob
5. Shim count: 18 → 17

### 7.6 Risk

| Factor | Assessment |
|--------|-----------|
| Core build impact | None — identical code |
| Behavior change | None — `DebugPrint()` is already a no-op |
| Business impact | None — debug timing only |
| WPF build impact | None — now in WPF tree |
