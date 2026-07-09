# B11 Audit: Platform Capability Wiring

**Status:** Audit only — no code or config changes
**Predecessor:** B10 structural shim cleanup complete

---

## 1. B11.1 Audit: BgiOnnxModel Deployment and Path Resolution

### 1.1 Current state

Core BgiOnnxModel defines 11 static ONNX model entries with hardcoded relative paths:

| Model | Core path (`ModelRelativePath`) |
|-------|-------------------------------|
| `YapModelTraining` | `Assets\Model\Yap\model_training.onnx` |
| `PaddleOcrDetV4` | `Assets\Model\PaddleOcr\ppocr_det_v4.onnx` |
| `PaddleOcrDetV5` | `Assets\Model\PaddleOcr\ppocr_det_v5.onnx` |
| `PaddleOcrDetV6` | `Assets\Model\PaddleOcr\ppocr_det_v6.onnx` |
| `PaddleOcrRecV4` | `Assets\Model\PaddleOcr\ppocr_rec_v4.onnx` |
| `PaddleOcrRecV4En` | `Assets\Model\PaddleOcr\ppocr_rec_v4_en.onnx` |
| `PaddleOcrRecV5` | `Assets\Model\PaddleOcr\ppocr_rec_v5.onnx` |
| `PaddleOcrRecV5Latin` | `Assets\Model\PaddleOcr\ppocr_rec_v5_latin.onnx` |
| `PaddleOcrRecV5Eslav` | `Assets\Model\PaddleOcr\ppocr_rec_v5_eslav.onnx` |
| `PaddleOcrRecV5Korean` | `Assets\Model\PaddleOcr\ppocr_rec_v5_korean.onnx` |
| `PaddleOcrRecV6` | `Assets\Model\PaddleOcr\ppocr_rec_v6.onnx` |

Core `BgiOnnxFactory.CreateInferenceSession(model)` uses `model.ModelRelativePath` directly — a raw relative path resolved against the process working directory.

### 1.2 Call chain

``` 
BgiOnnxFactory.CreateInferenceSession(model, ocr)
  → new InferenceSession(model.ModelRelativePath)
    → loaded by Det.cs:14, Rec.cs:22, PickTextInference.cs:28
```

All 3 callers are Core-linked and runtime-reachable from the macOS OCR pipeline.

### 1.3 WPF comparison

| Aspect | Core shim | WPF authoritative |
|--------|-----------|-------------------|
| Path resolution | `ModelRelativePath` (raw relative) | `ModalPath` → `Global.Absolute(ModelRelativePath)` |
| Session creation | `new InferenceSession(path)` | `new InferenceSession(path)` (same API) |
| Model source | External (not in repo) | External (not in repo) |
| Copy rules | **None** in Core csproj | **None** for `.onnx` in WPF csproj |
| ONNX Runtime package | `Microsoft.ML.OnnxRuntime 1.21.0` | Same + `DirectML` |

### 1.4 Model file availability

| Check | Result |
|-------|--------|
| `.onnx` files in repository? | **Zero** — no model files committed |
| `.gitignore` excludes them? | **No** — no onnx pattern in .gitignore |
| csproj copies them to output? | **No** — no `CopyToOutputDirectory` rules for `.onnx` in either csproj |
| WPF production loads them? | Yes — via `Global.Absolute()` resolving to publish directory or dev root |
| Core production can load them? | **No** — raw `ModelRelativePath` resolves against working directory; no files exist at any expected path |

**The `.onnx` model files are external runtime artifacts** in both WPF and Core projects. The WPF project relies on `Global.Absolute()` to resolve paths; the Core shim has no equivalent path-resolution mechanism. Even if model files were placed at the expected paths, the working directory would need to match.

### 1.5 Failure mode

`InferenceSession` construction will fail when the model path cannot be resolved. The exact exception type has not been verified — no test in the current 112/112 suite creates an `InferenceSession` or loads an `.onnx` file.

| Scenario | Result |
|----------|--------|
| `dotnet run` from repo root | `./Assets/Model/...` does not exist → session creation fails |
| `dotnet test` from any directory | Same — no model files in test output |
| macOS .NET host with published app | Same — no copy rule includes `.onnx` files |
| Swift host calling into .NET runtime | Same — model files not bundled |

### 1.6 macOS path separator constraint

Current `ModelRelativePath` values use Windows backslashes: `Assets\Model\PaddleOcr\ppocr_det_v4.onnx`. On Unix/macOS, `\` is NOT a directory separator — it's an ordinary filename character. `Path.Combine("/root", @"Assets\Model\...")` produces `/root/Assets\Model\...` — a path that does not exist.

**Any path resolution strategy must normalize backslashes first:**

```csharp
relativePath.Replace('\\', Path.DirectorySeparatorChar)
```

Or store registry paths with forward slashes or as path segments, not as Windows-specific literals. This applies regardless of whether the resolver uses `Global.Absolute`, `Path.Combine`, or injected model root.

### 1.7 Resolution options

| Option | Description | Core static dependency? | Host/composition control? | Cross-platform path? | Preferred? |
|--------|-------------|------------------------|--------------------------|---------------------|------------|
| **A** — `Global.Absolute` in BgiOnnxModel | Reuse `Global.Absolute()` to resolve ModalPath (mimics WPF) | ✅ Yes — static `Global` | ❌ No — hidden from composition | ⚠️ Needs normalization for `\` | ❌ **Not recommended** — re-introduces static path dependency B10 just removed |
| **B** — `IOnnxModelPathResolver` injection | New interface + implementation injected into BgiOnnxFactory | ❌ No — explicit constructor param | ✅ Yes — composition provides model root | ✅ Normalizes in resolver | ✅ **Recommended** |
| **C** — macOS bundle resources | Model files in `.app/Contents/Resources`; Swift host passes resource root | ❌ No | ✅ Yes | ✅ | Phase 2 |
| **D** — Download/verify script | Script pulls models from upstream release | N/A | N/A | N/A | Prerequisite for all |

### 1.8 Recommended plan (B11.1.1): explicit ONNX model path resolver

**Step 1: Define `IOnnxModelPathResolver` interface**

```csharp
// In BetterGenshinImpact.Core (new file, e.g. Core/Abstractions/Runtime/IOnnxModelPathResolver.cs)
namespace BetterGenshinImpact.Core.Abstractions.Runtime;

public interface IOnnxModelPathResolver
{
    string ResolveModelPath(BgiOnnxModel model);
    string ResolveCachePath(BgiOnnxModel model);
}
```

**Step 2: Implement `ModelRootPathResolver`**

```csharp
public sealed class ModelRootPathResolver : IOnnxModelPathResolver
{
    private readonly string _modelRoot;

    public ModelRootPathResolver(string modelRoot)
    {
        ArgumentNullException.ThrowIfNull(modelRoot);
        _modelRoot = modelRoot;
    }

    public string ResolveModelPath(BgiOnnxModel model)
    {
        var normalized = model.ModelRelativePath
            .Replace('\\', Path.DirectorySeparatorChar)
            .Replace('/', Path.DirectorySeparatorChar);
        return Path.GetFullPath(Path.Combine(_modelRoot, normalized));
    }

    public string ResolveCachePath(BgiOnnxModel model)
    {
        var normalized = model.CacheRelativePath
            .Replace('\\', Path.DirectorySeparatorChar)
            .Replace('/', Path.DirectorySeparatorChar);
        return Path.GetFullPath(Path.Combine(_modelRoot, normalized));
    }
}
```

**`_modelRoot` semantics:** The model root is the directory containing the `Assets` folder. This matches the `Global.Absolute` convention where the project root contains `Assets\Model\...`. If model files are moved to a flatter structure, the root changes accordingly — the resolver hides this from the registry.

**Step 3: Modify `BgiOnnxFactory` to accept `IOnnxModelPathResolver`**

```csharp
public class BgiOnnxFactory
{
    private readonly IOnnxModelPathResolver _pathResolver;

    public BgiOnnxFactory(IOnnxModelPathResolver pathResolver)
    {
        _pathResolver = pathResolver ?? throw new ArgumentNullException(nameof(pathResolver));
    }

    public InferenceSession CreateInferenceSession(BgiOnnxModel model, bool ocr = false)
    {
        var modelPath = _pathResolver.ResolveModelPath(model);
        return new InferenceSession(modelPath);
    }
}
```

This replaces the parameterless constructor. The `GetPpOcr*` dead methods were already removed in B10.17.1.

**Step 4: Wire through composition**

- **macOS production (MacAutoPickComposition):** Pass `new ModelRootPathResolver(systemModelRoot)` where `systemModelRoot` comes from the Swift host or app configuration
- **Verification:** Pass a resolver pointing to a test model directory, or create a resolver that throws `NotSupportedException` when called (tests that don't load models)
- **WPF:** Unchanged — WPF uses its own authoritative `BgiOnnxFactory` with `Global.Absolute`

**Step 5: Update Verification**

No change to existing 112/112 assertions. Add a new test verifying that `IOnnxModelPathResolver.ResolveModelPath` normalizes backslashes on all platforms (fast, no model file needed). Model loading itself remains uncovered.

### 1.9 Comparison: explicit resolver vs Global.Absolute

| Concern | Global.Absolute approach | IOnnxModelPathResolver approach |
|----------|-------------------------|----------------------------------|
| Static dependency | ✅ Yes — re-introduces `Global` static | ❌ No — explicit constructor param |
| Composition control | ❌ Hidden from host | ✅ Model root passed explicitly |
| Testability | ❌ Requires `Global.Absolute` behavior | ✅ Test resolver can throw or use test dir |
| macOS path normalize | ⚠️ Need `\` fix in resolver anyway | ✅ Built into resolver |
| WPF behavior change | None (different file) | None (WPF uses own factory) |

### 1.10 Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Model files still absent — path resolver alone doesn't make OCR work | **High** — models are external artifacts | Document as separate blocker. Path resolution and model deployment are independent. |
| `ModelRootPathResolver` adds complexity for what `Global.Absolute` already does in dev mode | **Low** — 30-line implementation; explicit contract enables testability and host control | Acceptable tradeoff; removes static dependency B10 just eliminated |
| WPF backslash path normalization not needed (WPF always runs on Windows) | **None** — Core's resolver normalizes; WPF's authoritative factory never uses Core's resolver | Separate implementations, no cross-impact |

### 1.11 Items deferred outside B11.1

- Actual `.onnx` model file deployment (externally managed)
- Model loading coverage in Verification (beyond resolver unit test)
- macOS bundle resource strategy
- WPF model path alignment (`PaddleOcr` vs `PaddleOCR/Det|Rec/V{n}/...` directory structure)

**Not deferred** — `BgiOnnxFactory` signature change propagation to Det.cs, Rec.cs, PickTextInference.cs is **in B11.1.1 implementation scope**. If `BgiOnnxFactory` gains a required `IOnnxModelPathResolver` constructor, all construction/call sites must be updated in the same commit.

### 1.12 B11.1.1 Implementation Result

| Component | Status |
|-----------|--------|
| `IOnnxModelPathResolver` interface | Added to `Core/Abstractions/Runtime/` (WPF tree, Core linked) ✅ |
| `ModelRootPathResolver` implementation | Added to `Adapters/` — normalizes `\` and `/` to `Path.DirectorySeparatorChar` ✅ |
| `ModelRootPathResolver` root validation | Rejects empty/whitespace; stores `Path.GetFullPath(modelRoot)` — no cwd fallback ✅ |
| `BgiOnnxFactory` constructor | Required `IOnnxModelPathResolver` — no more `model.ModelRelativePath` / `Global.Absolute` / cwd ✅ |
| Verification resolver test | Backslash normalization + empty/whitespace rejection + fully-qualified path ✅ |
| Verification assertion count | 112 → **115** (+3 resolver validation assertions) |
| Core build | 0 errors ✅ |
| WPF authoritative `BgiOnnxFactory` | **Unchanged** ✅ |

### 1.13 Remaining blockers (not in B11.1.1 scope)

| Blocker | Detail |
|---------|--------|
| `.onnx` model files absent | External artifacts — not committed, not deployed |
| Real InferenceSession test | Verification creates no InferenceSession; wiring-only |
| Core OCR production-ready | **False** — model files missing, sidecar paths unresolved |
| PaddleOCR sidecar files | `inference.yml`, label files, preheat images — still use `Global.Absolute` / raw `ModalPath` |
| macOS bundle resource strategy | Not addressed |

### 1.14 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 115/115 ✅
```

---

## 2. B11.2 Audit: PaddleOCR Sidecar Resource Path Resolution

### 2.1 Problem

B11.1.1 fixed `BgiOnnxFactory.CreateInferenceSession` to use `IOnnxModelPathResolver`, but PaddleOCR has additional resource files loaded outside the ONNX session path. These still use `Global.Absolute()` or raw `ModelRelativePath` — unnormalized, unresolved on macOS.

### 2.2 Sidecar resource inventory

| Resource | Path expression | Code location | Resolved by | Core-safe? |
|----------|----------------|---------------|-------------|------------|
| Test preheat image | `Global.Absolute(@"Assets\Model\PaddleOCR\test_pp_ocr.png")` | `PaddleOcrService.cs:40` — `static` field | `Global.Absolute` | ❌ Static, cwd-probing |
| Test number image | `Global.Absolute(@"Assets\Model\PaddleOCR\test_pp_ocr_number.png")` | `PaddleOcrService.cs:42-43` — `static` field | `Global.Absolute` | ❌ Same |
| `inference.yml` config | `Path.GetDirectoryName(recModel.ModalPath)` → `inference.yml` | `PaddleOcrService.cs:48-50` — `DefaultRecLabelFunc` | `recModel.ModalPath` (raw `ModelRelativePath` in Core) | ❌ Raw relative |
| Character label files | Derived from `inference.yml` or model directory | Same function | Same as above | ❌ |
| OCR model files (`.onnx`) | `BgiOnnxFactory.CreateInferenceSession(model)` via `IOnnxModelPathResolver` | `Det.cs`, `Rec.cs`, `PickTextInference.cs` | ✅ Fixed in B11.1.1 | ✅ |

### 2.3 Core BgiOnnxModel ModalPath still raw

```csharp
// Shim/BgiOnnxModel.cs:
public string ModalPath => ModelRelativePath;          // ← raw, unresolved
public string CachePath => CacheRelativePath;          // ← raw, unresolved
```

`DefaultRecLabelFunc` calls `Path.GetDirectoryName(recModel.ModalPath)` to find the model's directory, then reads `inference.yml` from it. In Core, `ModalPath` is `Assets\Model\PaddleOcr\ppocr_rec_v5.onnx` → directory = `Assets\Model\PaddleOcr\` → `inference.yml` would be `Assets\Model\PaddleOcr\inference.yml` — a relative path that only works if cwd matches.

### 2.4 TestImagePath is a static field — initialized once at class load

```csharp
public static string TestImagePath = Global.Absolute(...) ?? "";
```

This is a `static` field initializer. It runs when `PaddleOcrService` is first accessed. On Core, `Global.Absolute` probes the directory tree. This is the same static path dependency pattern B10 eliminated everywhere else.

### 2.5 Design constraints

| Constraint | Rationale |
|------------|-----------|
| `IOnnxModelPathResolver` must stay ONNX-model-only | Sidecar files (inference.yml, labels, PNG) are not ONNX models. Adding `ResolveSidecarPath` pollutes the interface contract. |
| `BgiOnnxModel.ModalPath` must NOT use resolver | `BgiOnnxModel` is a static registry with no resolver instance. Making `ModalPath` use a resolver would require static resolver / service locator — the pattern B11 eliminates. |
| `DefaultRecLabelFunc` must stop deriving paths from `recModel.ModalPath` | ModalPath is raw relative in Core. The `inference.yml` path must come from a resolver, not from the model registry property. |
| Static `TestImagePath` / `TestNumberImagePath` must be instance-resolved | Static field initializers with `Global.Absolute` are the pattern B10 removed. These must become lazy/instance-resolved via a resolver. |
| `PaddleOcrModelType.Build(...)` must accept resource resolver | The factory that creates `Det`/`Rec` pairs needs the resolver to pass to `Rec` for label/config resolution. |

### 2.6 Resolution options

| Option | Description | Impact |
|--------|-------------|--------|
| **A** — New `IOcrResourcePathResolver` interface | Separate interface for PaddleOCR-specific resources: `ResolveModelPath`, `ResolveModelDirectory`, `ResolveSidecarPath` | Clean separation; implementation can reuse normalization logic |
| **B** — Extend `IOnnxModelPathResolver` | Add `ResolveSidecarPath` | ❌ Interface pollution — ONNX model resolver shouldn't know about inference.yml |
| **C** — Fix `ModalPath` + `CachePath` in Core shim with `Global.Absolute` | Rejected per B11 direction | Re-introduces static path dependency |

**Recommendation: Option A** — new `IOcrResourcePathResolver` interface with `IOcrResourcePathResolver : IOnnxModelPathResolver` or standalone.

### 2.7 Recommended plan (B11.2.1)

1. Define `IOcrResourcePathResolver`:
   ```csharp
   public interface IOcrResourcePathResolver
   {
       string ResolveModelPath(BgiOnnxModel model);
       string ResolveModelDirectory(BgiOnnxModel model);
       string ResolveSidecarPath(string relativePath);
   }
   ```
   This can be a standalone interface (not extending `IOnnxModelPathResolver`). The `ModelRootPathResolver`-like implementation can be reused via shared normalization logic.

2. Implement `OcrResourcePathResolver` using same model-root + path-normalization pattern from `ModelRootPathResolver`.

3. Do NOT touch `BgiOnnxModel.ModalPath` / `CachePath`. They remain WPF compatibility properties. Core consumers must stop accessing them for runtime path resolution.

4. Replace `DefaultRecLabelFunc` closure with `RecLabel(resolver, recModel)` that uses `resolver.ResolveModelDirectory(recModel)` + `inference.yml`.

5. Convert static `TestImagePath` / `TestNumberImagePath` to instance lazy resolution via resolver.

6. `PaddleOcrModelType.Build(...)` — add `IOcrResourcePathResolver resourceResolver` parameter; pass to `Rec` and `PaddleOcrService`.

7. `OcrFactory.CreatePaddleOcrInstance()` — obtain resolver from constructor or composition; pass through `Build`.

8. `PaddleOcrService` constructor — accept `IOcrResourcePathResolver`; replace `Global.Absolute` calls.

### 2.8 No Global.Absolute, no ModalPath-based inference.yml

All sidecar paths must go through `IOcrResourcePathResolver`. No cwd fallback, no static resolver, no `BgiOnnxModel.ModalPath` property used for runtime path resolution.

### 2.9 Remaining blockers after B11.2.1

- `.onnx` model files still absent from repository
- Real `InferenceSession` loading test still deferred
- macOS bundle resource strategy not addressed
- Core OCR production-ready remains **False**

### 2.10 B11.2.1 Implementation Result (commits cc27535 → 1ec429e → 6f12bb4)

| Component | Status |
|-----------|--------|
| `IOcrResourcePathResolver` interface | Added to `Core/Abstractions/Runtime/` ✅ |
| `OcrResourcePathResolver` implementation | Added to `Adapters/` — root validation, path normalization ✅ |
| `OcrFactory` constructor | Core required `IOcrResourcePathResolver` (`#if BGI_PLATFORM_MAC`); WPF optional ✅ |
| `PaddleOcrService` constructor | Core required `IOcrResourcePathResolver` (`#if BGI_PLATFORM_MAC`); WPF optional ✅ |
| `PaddleOcrModelType.Build()` | Core required resolver; WPF optional ✅ |
| `OcrFactory.CreatePaddleOcrInstance()` | All 9 model branches pass `resourceResolver: _resourceResolver` ✅ |
| Preheat path resolution | Core uses `modelType.PreHeatImageRelativePath` via resolver; WPF unchanged ✅ |
| PaddleOCR labels | Core uses `LoadLabelsFromModel(resolver, recModel)` — no `recModel.ModalPath` ✅ |
| `V4En` model type availability | Core registered with `preHeatImageRelativePath` (not disabled) ✅ |
| `FromCultureInfoV4` English path | Returns `V4En` (same as WPF) — not downgraded to V5 ✅ |
| `TestImagePath` / `TestNumberImagePath` static fields | `#if !BGI_PLATFORM_MAC` guarded ✅ |
| `DefaultRecLabelFunc` | `#if !BGI_PLATFORM_MAC` guarded ✅ |
| `BgiOnnxModel.ModalPath` / `CachePath` | Unchanged — treated as WPF compatibility properties ✅ |
| Core `Global.Absolute` usage for PaddleOCR resources | Removed from Core preprocessing path ✅ |
| Verification resolver tests | OcrResourcePathResolver tests added (model path, directory, sidecar) ✅ |
| Assertion count | 115 → **118** (+3 resolver tests) |
| Core build | 0 errors ✅ |
| WPF build — new errors | **Zero** (same pre-existing TaskTriggerDispatcher errors) ✅ |

### 2.11 Remaining blockers

| Blocker | Detail |
|---------|--------|
| `.onnx` model files absent from repository | External artifacts — not committed, not deployed |
| Real `InferenceSession` loading test | Verification creates no `InferenceSession`; wiring-only |
| Sidecar resource files absent | inference.yml, label files, preheat images not present in repo |
| macOS bundle resource strategy | Not addressed |
| Core OCR production-ready | **False** — model files + sidecar files + bundle strategy unresolved |

### 2.12 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 118/118 ✅
```

---

## 3. B11.3 Audit: Model Artifact Contract and macOS Bundle Strategy

### 3.1 Two separate problems

The codebase has TWO independent issues with Paddle model paths:

**Problem 1 — Case convention:** Core `BgiOnnxModel` registry uses `PaddleOcr` (lowercase c); sidecar paths and WPF authoritative use `PaddleOCR` (uppercase C). On macOS case-sensitive APFS these are different directories.

**Problem 2 — Layout convention:** Core registry uses flat paths (`Assets\Model\PaddleOcr\ppocr_rec_v5.onnx`). WPF authoritative uses nested paths (`Assets\Model\PaddleOCR\Rec\V5\...\slim.onnx`). These are different layouts; case unification alone does not solve the sidecar layout.

### 3.2 Layout options

| Option | Description | `ResolveModelDirectory(recModel) + inference.yml` compatibility | Recommendation |
|--------|-------------|----------------------------------------------------------------|----------------|
| **A — Flat layout** | All .onnx files in `Assets/Model/PaddleOCR/` | ❌ Not compatible — multiple rec models share one directory, can't have per-model inference.yml | Not recommended |
| **B — Per-model directory layout** | Each model in its own subdirectory with inference.yml alongside | ✅ Each rec model has its own directory + inference.yml + dict files | ✅ **Recommended** |
| **C — Flat registry + resolver mapping** | Registry flat; resolver maps model to directory | ❌ Hidden mapping complexity, registry no longer reflects real path | Not recommended |

**Recommendation: Option B.** Per-model directory layout, with Core `BgiOnnxModel.ModelRelativePath` updated later to match the real artifact tree.

### 3.3 Required artifact inventory

#### Case convention
Unify to `PaddleOCR` (uppercase C, matching WPF authoritative and sidecar paths). Core `BgiOnnxModel` registry paths must change from `PaddleOcr` to `PaddleOCR`.

#### Per-model inventory

| Registry key | Core type | Current path | Recommended path | inference.yml needed? | Dict files needed? |
|-------------|-----------|-------------|------------------|-----------------------|--------------------|
| `YapModelTraining` | Yap OCR | `Assets\Model\Yap\model_training.onnx` | Same (no change) | ❌ | ❌ |
| `PaddleOcrDetV4` | Det only | `Assets\Model\PaddleOcr\ppocr_det_v4.onnx` | `Assets\Model\PaddleOCR\Det\V4\ppocr_det_v4.onnx` | ❌ | ❌ |
| `PaddleOcrDetV5` | Det only | `Assets\Model\PaddleOcr\ppocr_det_v5.onnx` | `Assets\Model\PaddleOCR\Det\V5\ppocr_det_v5.onnx` | ❌ | ❌ |
| `PaddleOcrDetV6` | Det only | `Assets\Model\PaddleOcr\ppocr_det_v6.onnx` | `Assets\Model\PaddleOCR\Det\V6\ppocr_det_v6.onnx` | ❌ | ❌ |
| `PaddleOcrRecV4` | Rec | `Assets\Model\PaddleOcr\ppocr_rec_v4.onnx` | `Assets\Model\PaddleOCR\Rec\V4\ppocr_rec_v4.onnx` | ✅ | ✅ |
| `PaddleOcrRecV4En` | Rec | `Assets\Model\PaddleOcr\ppocr_rec_v4_en.onnx` | `Assets\Model\PaddleOCR\Rec\V4En\ppocr_rec_v4_en.onnx` | ✅ | ✅ |
| `PaddleOcrRecV5` | Rec | `Assets\Model\PaddleOcr\ppocr_rec_v5.onnx` | `Assets\Model\PaddleOCR\Rec\V5\ppocr_rec_v5.onnx` | ✅ | ✅ |
| `PaddleOcrRecV5Latin` | Rec | `Assets\Model\PaddleOcr\ppocr_rec_v5_latin.onnx` | `Assets\Model\PaddleOCR\Rec\V5Latin\ppocr_rec_v5_latin.onnx` | ✅ | ✅ |
| `PaddleOcrRecV5Eslav` | Rec | `Assets\Model\PaddleOcr\ppocr_rec_v5_eslav.onnx` | `Assets\Model\PaddleOCR\Rec\V5Eslav\ppocr_rec_v5_eslav.onnx` | ✅ | ✅ |
| `PaddleOcrRecV5Korean` | Rec | `Assets\Model\PaddleOcr\ppocr_rec_v5_korean.onnx` | `Assets\Model\PaddleOCR\Rec\V5Korean\ppocr_rec_v5_korean.onnx` | ✅ | ✅ |
| `PaddleOcrRecV6` | Rec | `Assets\Model\PaddleOcr\ppocr_rec_v6.onnx` | `Assets\Model\PaddleOCR\Rec\V6\ppocr_rec_v6.onnx` | ✅ | ✅ |

#### Sidecar resources

| File | Placement rule | Used by |
|------|---------------|---------|
| `inference.yml` | Same directory as each Rec .onnx | Character dict / labels via `DefaultRecLabelFunc` → `LoadLabelsFromModel` |
| Character dict files | Same directory as each Rec .onnx (paths listed in `inference.yml PostProcess.character_dict`) | PaddleOCR Rec label decoding |
| `test_pp_ocr.png` | `Assets\Model\PaddleOCR\` | PaddleOcrService warmup (all models except V4En) |
| `test_pp_ocr_number.png` | `Assets\Model\PaddleOCR\` | PaddleOcrService warmup (V4En) |

### 3.4 Required artifact tree

```
<modelRoot>/
  Assets/
    Model/
      Yap/
        model_training.onnx
      PaddleOCR/
        test_pp_ocr.png
        test_pp_ocr_number.png
        Det/
          V4/  ppocr_det_v4.onnx
          V5/  ppocr_det_v5.onnx
          V6/  ppocr_det_v6.onnx
        Rec/
          V4/       ppocr_rec_v4.onnx  + inference.yml + <dict files>
          V4En/     ppocr_rec_v4_en.onnx  + inference.yml + <dict files>
          V5/       ppocr_rec_v5.onnx  + inference.yml + <dict files>
          V5Latin/  ppocr_rec_v5_latin.onnx  + inference.yml + <dict files>
          V5Eslav/  ppocr_rec_v5_eslav.onnx  + inference.yml + <dict files>
          V5Korean/ ppocr_rec_v5_korean.onnx  + inference.yml + <dict files>
          V6/       ppocr_rec_v6.onnx  + inference.yml + <dict files>
```

The `ResolveModelDirectory(recModel)` for `PaddleOcrRecV5` returns `<modelRoot>/Assets/Model/PaddleOCR/Rec/V5/`, and `inference.yml` is `<modelRoot>/Assets/Model/PaddleOCR/Rec/V5/inference.yml`. Each Rec model's character dict is local to its directory.

### 3.5 Artifact source strategy comparison

| Option | Repo impact | Reproducibility | macOS bundle | CI | Recommendation |
|--------|-------------|----------------|--------------|-----|---------------|
| **A. Download script** | Zero (script only) | ✅ Deterministic with pinned version | Download at build/install time | ✅ CI can cache | ✅ **Dev/test** |
| **B. Git LFS** | Large (100s MB) | ✅ | LFS checkout | ✅ Needs LFS | ❌ Too large |
| **C. Build-time copy from upstream** | Zero | ⚠️ Upstream availability | Copy as build step | ⚠️ | Acceptable for CI |
| **D. macOS app bundle Resources** | Zero | ✅ | Part of `.app` packaging | N/A | ✅ **Final distribution** |

### 3.6 Recommended strategy

1. **Dev/test/CI:** Download script pulls pinned-version artifacts to local model root. No check-in, no LFS.
2. **macOS distribution:** Artifacts bundled into `.app/Contents/Resources/BetterGI/`. Swift host passes absolute path to resolvers.
3. **Registry update:** After layout decision is stable, update Core `BgiOnnxModel.ModelRelativePath` values to match `PaddleOCR/Det|Rec/V{n}/` layout.

### 3.7 Validation plan

| Check | Method | Artifacts required? |
|-------|--------|---------------------|
| Path resolution matches registry | `Path.GetFullPath(resolver.ResolveModelPath(model))` per registry entry | ❌ No |
| Sidecar path resolves | `resolver.ResolveSidecarPath(relativePath)` | ❌ No |
| Missing ONNX failure shape | When artifacts are intentionally absent, capture and document actual exception type from `InferenceSession` construction | ✅ Yes |
| Case-sensitivity on APFS | Verify `PaddleOCR` directory resolves correctly on case-sensitive volume | Manual |
| Real ONNX inference | `InferenceSession.Run()` with sample input | ✅ Yes |

Do not assert `FileNotFoundException` until the actual exception type has been verified from a real `InferenceSession` constructor call.

### 3.8 Out-of-scope items

- Writing the download script
- Committing `.onnx` / `.yml` / `.png` / dict files
- Implementing macOS bundle copy rules in Swift/Xcode
- Real `InferenceSession` inference test
- WPF artifact handling (continues using existing `Global.Absolute` path)

### 3.9 Recommended implementation sequence

| Phase | Scope | Artifacts required? |
|-------|-------|---------------------|
| **B11.4** — Registry path alignment | Update Core `BgiOnnxModel.ModelRelativePath` to match chosen `PaddleOCR/Det|Rec/V{n}/` layout. Update Verification expected path tests. | ❌ No |
| **B11.5** — Artifact manifest | Create manifest file listing all expected artifact relative paths. Validate path resolution without model files. | ❌ No |
| **B11.6** — Download script / bundle strategy | Implement download script and macOS bundle packaging. | ✅ Yes |

Each phase builds on the previous one. Registry must reflect real artifact layout before manifest can be authored.

### 3.10 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 118/118 ✅
```
