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
