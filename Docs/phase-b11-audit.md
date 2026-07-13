# B11 Audit: Platform Capability Wiring

**Status:** B11.1–B11.5.1 and B11.2.2 complete; B11.6.1 provenance audited, source-lock created; B11.6.2 downloader prohibited. Core OCR production-ready remains false.
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
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 288/288 ✅
```


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

### 2.5 Baseline validation

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 288/288 ✅
```

Note: At this historical B11.2.1 baseline, the Yap dictionary contract was not yet covered; B11.2.2 later closed it.

---

### 2.6 B11.2.2 Yap dictionary path implementation

| Item | Detail |
|------|--------|
| a6df841 (initial) | Core PickTextInference requires IOcrResourcePathResolver; YapDictionaryRelativePath constant; Windows/WPF preserves original single-parameter API and Global.Absolute |
| f438ec3 (correction) | Exact constructor/factory API contract locked via reflection verification; _wordDictionary restored to private readonly; LoadWordDictionary returns Dictionary; factory null-resolver fail-fast test |
| Yap dictionary path | `"Assets/Model/Yap/index_2_word.json"` — matches manifest sidecar |
| Core constructor params | (BgiOnnxFactory, IOcrResourcePathResolver) — both required, not optional |
| Factory params | (OcrEngineTypes, BgiOnnxFactory, IOcrResourcePathResolver) — all required, not optional |
| Core/macOS Global.Absolute | **Removed** — uses resolver.ResolveSidecarPath |
| Windows Global.Absolute | Preserved — unchanged |
| Static resolver / service locator / fallback | **None** |
| Real JSON delivered? | **No** |

### 2.7 B11.2.2 Validation result

| Test | Result |
|------|--------|
| Core build | Passed |
| B11.2.2 section assertions | 18/18 passed |
| Constructor exact contract | Single ctor, (BgiOnnxFactory, IOcrResourcePathResolver), both non-optional |
| Factory exact contract | Single Create overload, 3 required params, resolver at position 3 |
| PickTextInference null-resolver fail-fast | ArgumentNullException with ParamName "resourceResolver" before session creation |
| Factory null-resolver fail-fast | Same exception before switch/object creation |
| Manifest constant binding | PickTextInference.YapDictionaryRelativePath matches manifest sidecar |
| Full Verification rerun | Incomplete — stopped by pre-existing OpenCV native loading failure later in suite |
| Full-suite N/N | Not claimed |

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

**ONNX models (11 + 1 Yap JSON):** 1 Yap ONNX + 1 Yap JSON + 3 Det + 7 Rec. Paths align to `PaddleOCR/Det|Rec/V{n}/`.

**Sidecar resources:**
- 7 × `inference.yml` (one per Rec model directory)
- 1 × `index_2_word.json` (Yap runtime dictionary)
- 2 × preheat PNG (`test_pp_ocr.png`, `test_pp_ocr_number.png`)
- **No external dictionary files.** `PostProcess.character_dict` is an inline YAML sequence.
- Total physical files: **21**

### 3.4 Required artifact tree

```
<modelRoot>/
  Assets/
    Model/
      Yap/
        model_training.onnx
        index_2_word.json
      PaddleOCR/
        test_pp_ocr.png
        test_pp_ocr_number.png
        Det/
          V4/
            ppocr_det_v4.onnx
          V5/
            ppocr_det_v5.onnx
          V6/
            ppocr_det_v6.onnx
        Rec/
          V4/
            ppocr_rec_v4.onnx
            inference.yml
          V4En/
            ppocr_rec_v4_en.onnx
            inference.yml
          V5/
            ppocr_rec_v5.onnx
            inference.yml
          V5Latin/
            ppocr_rec_v5_latin.onnx
            inference.yml
          V5Eslav/
            ppocr_rec_v5_eslav.onnx
            inference.yml
          V5Korean/
            ppocr_rec_v5_korean.onnx
            inference.yml
          V6/
            ppocr_rec_v6.onnx
            inference.yml
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
| `15ae5f2` | B11.5.1 | Added `Assets/Model/Yap/index_2_word.json` to destination manifest; 21-file physical count; Yap path/resolver contract. No real artifacts. |
| `77277dc` | B11.5.1 fix | Yap sidecar same-directory assertion uses model directory (not hardcoded string); Rec/Det identification via Ordinal `StartsWith`. |

### 5.2 State before B11.5.1 reopening

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

### 5.3 Reopening reason (historical)

Before 15ae5f2, the manifest modeled 20 physical files. The Yap runtime dictionary (`Assets/Model/Yap/index_2_word.json`) was discovered during B11.6.1 provenance audit and was not in the manifest. B11.5 was reopened. 15ae5f2 added the missing sidecar; 77277dc added the true same-directory assertion. B11.5.1 is now complete.

### 5.4 Required B11.5.1 correction (completed in 15ae5f2, final assertion fix in 77277dc)

- Add `Assets/Model/Yap/index_2_word.json` to destination manifest
- Add path/resolver Verification for the Yap dictionary
- Update artifact counts from 20 to 21
- No real artifact files required — manifest/Verification only

### 5.5 Historical baseline (pre-reopening)

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 288/288 ✅
```

### 5.6 B11.5.1 Final state

| Component | Status |
|-----------|--------|
| ONNX model paths | 11 — all registry keys validated against resolver ✅ |
| Model-bound sidecar paths | 8 (7 inference.yml + 1 Yap index_2_word.json) ✅ |
| Global/preheat sidecars | 2 (test_pp_ocr.png, test_pp_ocr_number.png) ✅ |
| Total physical paths | 21, all Ordinal-unique ✅ |
| Rec sidecars in model dir | All 7 Rec verified — same-directory, filename inference.yml ✅ |
| Yap JSON same-directory | Verified — index_2_word.json in Assets/Model/Yap alongside ONNX ✅ |
| Real artifacts delivered? | **No** |
| File.Exists / InferenceSession? | **No** |
| Core OCR production-ready | **False** |

### 5.7 B11.5.1 Validation result

| Test | Result |
|------|--------|
| Core build | Passed |
| B11.5 manifest section | All assertions passed |
| Full Verification rerun | Incomplete — stopped by pre-existing OpenCV native loading failure later in the suite |
| Exception | TypeInitializationException → DllNotFoundException for OpenCvSharpExtern |
| Native library | OpenCvSharpExtern (not available on this macOS environment) |
| Full-suite N/N | Not claimed — historical 288/288 belongs to the old 20-file baseline |
| B11.5 section assertions | Passed before the later OpenCV failure |

---

## 6. B11.6 Audit: Artifact Delivery and macOS Bundle Strategy

### 6.1 Current status

B11.1–B11.4 and the PaddleOCR portion of B11.5 are implemented. B11.5.1 (15ae5f2) added the Yap runtime dictionary to the destination manifest, closing B11.5 again. B11.2.2 remains open because `PickTextInference` still resolves that dictionary through `Global.Absolute`.

**Core OCR not production-ready** — artifact files are not tracked in the repository and have not been delivered to a configured `modelRoot`. The key blockers are:

| Blocker | Detail |
|---------|--------|
| `.onnx` model files absent | 11 ONNX files required — not delivered to a configured modelRoot |
| `index_2_word.json` not delivered | Modeled in destination manifest (B11.5.1), no real file tracked or delivered to modelRoot |
| `inference.yml` sidecars absent | 7 Rec label configs required — not delivered |
| Preheat PNG images absent | 2 PNG files required — not delivered |
| Real InferenceSession test | Deferred — requires validated artifact set |
| macOS bundle strategy | Not implemented |
| Swift host path definition | Not defined |
| Artifact provenance | Audited in B11.6.1; source-lock created; overall CONDITIONAL |

### 6.2 modelRoot contract (corrected)

The resolver input `modelRoot` is the directory containing `Assets/`. Manifest `relativePath` values are relative to `modelRoot`.

**Correct example:**
```
modelRoot = /Users/dev/project/artifacts/model-root/
artifact  = modelRoot/Assets/Model/PaddleOCR/Rec/V5/ppocr_rec_v5.onnx
```

**Incorrect (would double up):**
```
modelRoot = /Users/dev/project/Assets/Model/
artifact  = modelRoot/Assets/Model/...  ← WRONG: double Assets/Model/
```

#### Recommended development staging

Download target:
```
<repo>/artifacts/model-root/
  Assets/
    Model/
      Yap/model_training.onnx
      Yap/index_2_word.json
      PaddleOCR/Det|Rec/...
```

Command semantics:
```
download-artifacts.sh --model-root <repo>/artifacts/model-root
```

CI example:
```
<workspace>/artifacts/model-root/
```

macOS bundle:
```
BetterGI.app/Contents/Resources/BetterGI/   ← this IS the modelRoot
  Assets/
    Model/
      ...
```

#### Git staging policy

- Repo root `/artifacts/` is already git-ignored (`.gitignore`)
- Dev/CI download location: `<repo>/artifacts/model-root/`
- **Do NOT** use `<repo>/Assets/Model/` — that is the source tree and is tracked by git
- The downloader must never modify the tracked source tree
- Bundle packaging copies from staging root: `<stagingRoot>/Assets` → `<app>/Contents/Resources/BetterGI/Assets`
- No runtime model artifact is committed to git, including:
- `*.onnx`
- `inference.yml`
- PaddleOCR preheat PNGs
- `Assets/Model/Yap/index_2_word.json`

### 6.3 Artifact source strategy candidates

#### Option A: Git LFS
- Store artifacts in a separate LFS-enabled repository
- Clone includes artifacts automatically (with LFS setup)
- Single source of truth, versioned with code
- **Pros**: Reproducible, CI-friendly, offline-capable after clone
- **Cons**: LFS bandwidth/quota costs, larger initial clone
- **Verdict**: Not recommended for this project — LFS is a workflow burden for occasional contributors and adds storage cost

#### Option B: Pinned external artifact archive
- Published as a release asset (e.g., GitHub Release `.tar.gz`/`.zip`)
- Download script fetches and extracts to correct layout
- Checksum verification after download
- Script runs at dev setup and CI time
- **Pros**: No repo bloat, CI-controllable, clear licensing boundary
- **Cons**: External dependency availability, extra setup step for new devs
- **Verdict**: Recommended for dev/test/CI — simple, auditable, no LFS dependency

#### Option C: macOS app bundle Resources
- Artifacts placed in `.app/Contents/Resources/BetterGI/` by a build/post-build step
- Swift host resolves root from `Bundle.main.resourceURL`
- .NET host receives path from Swift
- **Pros**: Self-contained app, no setup for end user
- **Cons**: Requires packaging infrastructure
- **Verdict**: Recommended for distribution — separate from dev/CI setup

#### Option D: Three-in-one hybrid
- **Dev/CI**: `download-artifacts.sh --model-root <repo>/artifacts/model-root`
- **macOS package**: `post-build` step copies artifact tree into `BetterGI.app/Contents/Resources/BetterGI/`
- Each environment explicitly passes its `modelRoot` to resolvers
- **Verdict**: **Recommended** — covers all environments without straying from the resolver contract

### 6.4 Destination manifest vs source lock

**`model-artifacts.manifest.json`** (existing — B11.5) is a **destination contract**:
- Defines expected artifact IDs, target relative paths, registry mapping, sidecars
- Does NOT contain source URL, checksum, or license
- Downloader cannot use it alone as a source of truth

**`model-artifacts.source-lock.json`** (proposed — B11.6.1) is a **source contract**:
- Pins an artifact set to one or more immutable sources
- Records verifiable provenance and redistribution constraints
- Allows download script to have a deterministic, auditable input

#### Proposed source-lock schema

```json
{
  "schemaVersion": 1,
  "artifactSetVersion": "<verified upstream version>",
  "sources": [
    {
      "id": "<source-id>",
      "type": "archive|raw-file",
      "url": "<verified immutable download URL>",
      "sha256": "<verified lowercase hex>",
      "format": "zip|7z|tar.gz|raw",
      "sizeBytes": 0,
      "provenance": {
        "project": "<source project name>",
        "releaseOrCommit": "<upstream tag/version/commit>",
        "sourcePage": "<authoritative project page>",
        "license": "<verified SPDX identifier or unverified>",
        "redistributionStatus": "allowed | restricted | unverified"
      }
    }
  ],
  "artifacts": [
    {
      "destinationRelativePath": "Assets/Model/<path>",
      "sourceId": "<source-id from sources[]>",
      "memberPath": "<path within source archive, or full raw URL>",
      "sha256": "<verified lowercase hex>",
      "transformation": "none | relocate | rename"
    }
  ]
}
```

**Notes:**
- `sources[]` is always an array, even with a single source
- `transformation` only covers simple remap (relocate, rename). Model conversion (Paddle inference → ONNX) is NOT a transformation — it requires a separate reproducible pipeline
- No placeholder lock file or URL may be committed
- Pattern A (archive matches manifest layout) must be verified, not assumed

**This audit only defines the schema.** Actual values remain deferred until B11.6.1.x delivery-container inspection and provenance follow-up resolves immutable URLs, hashes, mappings, and redistribution status. No placeholder URL, checksum, or license may be committed.

#### Archive-to-destination mapping

Two possible patterns (to be determined during provenance audit):

**Pattern A — Archive matches manifest layout:**
- Archive already contains `Assets/Model/Yap/...`, `Assets/Model/PaddleOCR/...`
- Extract directly under modelRoot
- No mapping table needed
- `contentRoot` in source-lock is `Assets/Model/`

**Pattern B — Upstream uses different layout:**
- Archive has non-matching directory structure or filenames
- Downloader needs an explicit remap table
- Each destination `relativePath` maps to an archive member
- Cannot be guessed from registry key
- Must be verified during provenance audit

### 6.5 Provenance and license audit — prerequisite

License/copyright review **cannot** be deferred to after download/packaging implementation. It is a prerequisite for B11.6.2+.

B11.6.1 must:
- Identify the authoritative source for each artifact category (ONNX models, inference.yml, preheat PNGs)
- Identify exact upstream release/tag/commit
- Verify immutable download URL (not a latest/redirectable link)
- Calculate and record SHA-256
- Inspect archive member tree to determine content layout
- Identify license(s) for ONNX models, inference.yml config files, and PNG images
- Determine whether redistribution inside macOS `.app` is allowed
- Determine required LICENSE/NOTICE attribution (must be bundled in `.app` if required)
- If redistribution status is **unverified** or **restricted**:
  - Pause downloader implementation
  - Pause bundle packaging
  - Do not self-upload as GitHub Release mirror
  - Document as blocker

### 6.6 Failure semantics (per layer)

| Layer | Failure mode |
|-------|-------------|
| Shell downloader | Non-zero exit code; detailed stderr; download into `mktemp` dir; cleanup on failure; no partially installed tree |
| .NET artifact validator (B11.6.3) | May throw `FileNotFoundException` with complete missing-path list |
| `InferenceSession` smoke test (B11.6.6) | Record actual exception type — do **not** assume `FileNotFoundException` until verified |

### 6.7 Downloader safety requirements (pre-design)

When B11.6.2 download script is implemented, it must satisfy:

- `set -euo pipefail`
- `curl --fail --location` (no `--silent` that hides errors)
- Required `--model-root <dir>`, no default value
- Canonicalize and print absolute model root before starting
- Download into `mktemp` directory (not directly into final location)
- Verify archive SHA-256 against source-lock **before** extraction
- Reject absolute archive member paths and `..` traversal members
- Do not extract directly into model root — use a staging temp tree
- Validate all manifest destinations exist in staged tree before install
- Atomic install (`mv` or `rsync` with temp dir, then swap)
- Cleanup trap on exit (remove temp download and extraction dirs)
- Idempotent: re-running with same model root and version is a no-op
- Explicit `--force` flag to overwrite existing artifacts
- No `sudo`
- Never modify tracked source tree (no writes under repo root except `artifacts/`)
- No silent network fallback (no unversioned `/latest` URLs)
- `--version` flag to print artifact set version from source-lock

### 6.8 Phase sequence (corrected)

Two independent workstreams:

**Immediate internal correctness (completed):**
| Phase | Status | Result |
|-------|--------|--------|
| B11.5.1 | Completed | 21-file destination manifest |
| B11.2.2 | Completed | Explicit Yap sidecar resolver injection through required IOcrResourcePathResolver |

**Provenance-gated delivery work (requires artifact source-lock):**
| Phase | Scope | Artifacts needed? |
|-------|-------|-------------------|
| B11.6.1.x | Release/container inspection — extract model files from upstream release, verify SHA-256 | Yes |
| Source lock | Create `model-artifacts.source-lock.json` with `sources[]` array | Yes |
| B11.6.2 | Implement `download-artifacts.sh` — consumes source-lock; `--model-root` required; SHA-256 verification; atomic install | No (script logic) |
| B11.6.3 | Add opt-in .NET artifact validator — verify 11 ONNX + 1 Yap JSON + 7 inference.yml + 2 PNG = 21 files; no InferenceSession yet | Yes |
| B11.6.4 | macOS bundle post-build copy step | Yes (from modelRoot staging) |
| B11.6.5 | Swift host passes `Bundle.main.resourceURL`/`BetterGI` as model root | No (path string only) |
| B11.6.6 | Gated real `InferenceSession` smoke test | Yes |

### 6.9 Out of scope

- Actual artifact download implementation (deferred to B11.6.2)
- macOS `.app` bundle packaging script (B11.6.4)
- Swift host code changes (B11.6.5)
- CI workflow definition
- `character_dict_path` support (not currently implemented)
### 6.10 Baseline (pre-implementation)

```
dotnet build BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj  → zero errors ✅
dotnet run --project Test/BetterGenshinImpact.Core.Verification/...    → 288/288 ✅
```

### 6.11 B11.6.1 Provenance Audit Result

See detailed report: [`Docs/b11.6.1-artifact-provenance.md`](b11.6.1-artifact-provenance.md)

| Aspect | Verdict |
|--------|---------|
| Destination manifest coverage | 21 physical paths modeled; historical `index_2_word.json` omission resolved by B11.5.1 (15ae5f2 + 77277dc) |
| Yap ONNX + JSON source | Authoritative source found: `Alex-Beng/Yap` commit `c5c9990` (GPL-3.0); byte identity with BetterGI **unverified** |
| PaddleOCR ONNX (10) | Apache-2.0 candidate; exact bytes/conversion chain **unverified** |
| Preheat PNGs | **Unresolved** — copyright unverified |
| inference.yml content | **Unresolved** — must verify inline `character_dict` |
| Delivery container | BetterGI 0.62.0 installer (454 MB); member tree **not inspected** |
| Source topology | Multi-provenance likely; single-archive not confirmed |
| **Overall** | **NO-GO** |

**Active blockers:**
- [ ] BetterGI installer/7z member tree not inspected
- [ ] Yap model SHA-256 not compared with BetterGI
- [ ] GPL-3.0 coverage of Yap model weights unclarified
- [ ] Preheat PNG provenance unknown
- [ ] inference.yml format unverified
- [ ] Paddle→ONNX conversion pipeline undocumented

**Resolved findings:**
- B11.5 manifest omission — resolved by 15ae5f2
- Yap same-directory relationship assertion — corrected by 77277dc
- Destination manifest now models 21 physical paths
- Core/macOS Global.Absolute removed from PickTextInference — resolved by a6df841
- Exact constructor/factory resolver contract locked — f438ec3

### 6.12 Phases opened by audit and current status

B11.5.1 and B11.2.2 are complete. The next work is B11.6.1.x evidence collection, but source-lock and downloader remain blocked by provenance.

| Phase | Status | Result / next action |
|-------|--------|----------------------|
| B11.5.1 | Completed | Manifest includes Yap JSON; 21 physical paths; final relationship assertion in 77277dc |
| B11.2.2 | Completed | a6df841 + f438ec3; Core/macOS no Global.Absolute; exact constructor/factory API locked |
| B11.6.1 (1.1–1.4) | **Completed** | Source-lock created: `model-artifacts.source-lock.json` with immutable archive hash, 21 artifact SHA-256, per-artifact license and provenance |
| B11.6.2 | NO-GO | Do not implement downloader (not yet started) |

---

