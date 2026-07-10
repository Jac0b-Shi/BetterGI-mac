# B11 Audit: Platform Capability Wiring

**Status:** B11.1–B11.5 implemented and locally verified; B11.6 artifact delivery/packaging remains open.
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
| PaddleOCR sidecar files | `inference.yml` (inline `PostProcess.character_dict`), preheat images — no external dict files required |
| macOS bundle resource strategy | Not addressed |

### 1.14 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 118/118 ✅
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
| OCR model files (`.onnx`) | `BgiOnnxFactory.CreateInferenceSession(model)` via `IOnnxModelPathResolver` | `Det.cs`, `Rec.cs`, `PickTextInference.cs` | ✅ Fixed in B11.1.1 | ✅ |

**`PostProcess.character_dict` is an inline YAML sequence inside `inference.yml`.** No external dictionary files are required. `ParseInferenceYml()` reads character labels directly from the YAML stream. `character_dict_path` is not currently implemented.

### 2.3 Design decisions

| Decision | Rationale |
|----------|-----------|
| `IOcrResourcePathResolver` separate from `IOnnxModelPathResolver` | Sidecar files (inference.yml, PNG) are not ONNX models |
| `BgiOnnxModel.ModalPath` NOT resolver-backed | Static registry; using resolver would require service locator |
| Core uses `ResolveModelDirectory(recModel)` + `inference.yml` | Not `recModel.ModalPath` |
| OcrFactory / PaddleOcrService / Build require resolver in Core | Required param in `#if BGI_PLATFORM_MAC`; optional on WPF |
| Preheat path model-specific via `PreHeatImageRelativePath` | Each model variant has its own preheat image |
| V4En available in Core | Not disabled — model selection preserved |

### 2.4 Implementation result (B11.2.1)

- `IOcrResourcePathResolver` interface + `OcrResourcePathResolver` implementation added
- PaddleOCR labels use `LoadLabelsFromModel(resolver, recModel)` — no `recModel.ModalPath`
- Core preheat uses `ResolveSidecarPath(modelType.PreHeatImageRelativePath)`
- WPF static `TestImagePath`/`TestNumberImagePath` guarded with `#if !BGI_PLATFORM_MAC`
- V4En restored; `FromCultureInfoV4` English returns V4En (not V5)
- No real artifact files delivered
- Core OCR production-ready remains false

---

## 3. B11.3 Audit: Model Artifact Contract and macOS Bundle Strategy

### 3.1 Two separate problems

**Problem 1 — Case convention:** Core `BgiOnnxModel` registry uses `PaddleOcr` (lowercase c); sidecar paths and WPF authoritative use `PaddleOCR` (uppercase C). On macOS case-sensitive APFS these are different directories.

**Problem 2 — Layout convention:** Core registry uses flat paths. WPF authoritative uses nested paths. Case unification alone does not solve the sidecar layout.

### 3.2 Layout decision: per-model directories

| Option | Result |
|--------|--------|
| **A — Flat layout** | ❌ Rejected — multiple Rec models share one directory, breaks per-model inference.yml |
| **B — Per-model directory layout** | ✅ **Selected** — each model in its own directory with inference.yml |
| **C — Flat registry + resolver mapping** | ❌ Rejected — hidden mapping complexity |

### 3.3 Required artifact inventory

**Case convention:** `PaddleOCR` (uppercase C).

**ONNX models (11):** 1 Yap + 3 Det + 7 Rec. Paths align to `PaddleOCR/Det|Rec/V{n}/`.

**Sidecar resources:**
- 7 × `inference.yml` (one per Rec model directory)
- 2 × preheat PNG (`test_pp_ocr.png`, `test_pp_ocr_number.png`)
- **No external dictionary files.** `PostProcess.character_dict` is an inline YAML sequence.

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
        Det/ V4/ppocr_det_v4.onnx
            V5/ppocr_det_v5.onnx
            V6/ppocr_det_v6.onnx
        Rec/
          V4/       ppocr_rec_v4.onnx + inference.yml
          V4En/     ppocr_rec_v4_en.onnx + inference.yml
          V5/       ppocr_rec_v5.onnx + inference.yml
          V5Latin/  ppocr_rec_v5_latin.onnx + inference.yml
          V5Eslav/  ppocr_rec_v5_eslav.onnx + inference.yml
          V5Korean/ ppocr_rec_v5_korean.onnx + inference.yml
          V6/       ppocr_rec_v6.onnx + inference.yml
```

### 3.5 Artifact source strategy

| Layer | Strategy |
|-------|----------|
| Dev/test/CI | Download script — pinned-version archive, no check-in, no LFS |
| macOS distribution | `.app/Contents/Resources/BetterGI/` — Swift host passes absolute path as model root |
| Registry | Core `BgiOnnxModel.ModelRelativePath` updated to match layout |

### 3.6 macOS bundle root

```
.app/Contents/Resources/BetterGI/   ← modelRoot passed to resolvers
  Assets/Model/Yap/...
  Assets/Model/PaddleOCR/Det|Rec/...
```

Resolver `modelRoot` is the directory containing `Assets/`.

### 3.7 Validation plan

- Manifest/registry string validation does not require artifacts
- Future real file validation requires artifacts
- Future gated InferenceSession smoke test
- No cwd fallback

---

## 4. B11.4 Registry Path Alignment

### 4.1 Implementation (commit 8225fa1 + correction)

| Change | Detail |
|--------|--------|
| Updated 10 PaddleOCR registry paths | `PaddleOcr` lowercase-c → `PaddleOCR` uppercase-C with `Det/` and `Rec/` subdirectories |
| Unchanged | `YapModelTraining` path (`Assets\Model\Yap\...`) |
| Layout model | `PaddleOCR/Det/V{n}/ppocr_det_v{n}.onnx` for detection; `PaddleOCR/Rec/V{n}/ppocr_rec_v{n}.onnx` for recognition |
| Rec directory significance | `ResolveModelDirectory(PaddleOcrRecV5)` returns `<root>/Assets/Model/PaddleOCR/Rec/V5`, compatible with `+ "inference.yml"` |
| Verification | DetV5 path test, RecV5 directory test, case-sensitivity guard (`PaddleOCR` present, `PaddleOcr` absent) |
| Assertion count | 118 → **121** (+3 Rec directory + case guard) |
| Artifacts delivered? | **No** — registry alignment only |
| Real `InferenceSession` created? | **No** |
| Core OCR production-ready? | **False** |

### 4.2 Next phase

**B11.5 Artifact manifest** — Create a manifest file listing all expected artifact relative paths. Validate resolution without model files. Do not download artifacts.

### 4.3 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 121/121 ✅
```

---

## 5. B11.5 Artifact Manifest

### 5.1 Implementation history

| Commit | Status | Key changes |
|--------|--------|-------------|
| `bdab13b` | Initial | Manifest JSON + DTO classes + basic parse test. 11 ONNX + 2 preheat entries. 130/130. |
| `65e814f` | Correction 1 | Added loader, 11-entry full registry validation, dynamicSidecars (incorrect — assumed external dict files). 259/259. |
| `f683f87` | Correction 2 | Removed false dynamicSidecars; Rec inference.yml contract; leaveOpen stream. 281/281. |
| `181ba56` | Final code/verification correction | Added strict `inference.yml` filename assertions; docs cleanup accidentally removed B11.2/B11.3. Local Verification: 288/288. |
| `33f0893` | Docs closure | Restored B11.2/B11.3, corrected inline `character_dict` documentation, updated top-level status and final B11.5 record. No production-code changes. |

### 5.2 Final state

| Component | Status |
|-----------|--------|
| Manifest file | `Manifest/model-artifacts.manifest.json` ✅ |
| Loader | `ModelArtifactManifestLoader.Load(Stream)` + `Parse(string)` — uses `leaveOpen: true` ✅ |
| ONNX model entries | 11 (1 Yap + 3 Det + 7 Rec) — all registry keys validated against `BgiOnnxModel` ✅ |
| Preheat sidecar entries | 2 (`test_pp_ocr.png` + `test_pp_ocr_number.png`) — both path-validated ✅ |
| Rec sidecar contract | 7 × `inference.yml` — each in its own model directory, path-validated ✅ |
| Character dict | Inline YAML sequence in `inference.yml` — no external dict files required ✅ |
| Real artifacts delivered? | **No** |
| `File.Exists` / `InferenceSession`? | **No** |
| Core OCR production-ready | **False** |

### 5.3 Next phase

**B11.6** — Download script / bundle packaging strategy.

### 5.4 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 288/288 ✅
```
