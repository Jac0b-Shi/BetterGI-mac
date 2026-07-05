# B9 Audit: OCR/Yap Static Gateway Extraction

**Status:** Audit only — no code changes
**Predecessor:** B8.3 complete (commit `d0c3f87`, Core Verification 100/100)

---

## 1. All OCR/Yap Call Sites in AutoPickTrigger.OnCapture()

All in `BetterGenshinImpact/GameTask/AutoPick/AutoPickTrigger.cs`, inside `OnCapture()`:

| Line | Code | Engine | Input Mat | Disposal |
|------|------|--------|-----------|----------|
| 300 | `config.OcrEngine == nameof(PickOcrEngineEnum.Yap)` | Selection | — (config read) | — |
| 302 | `new Mat(content.CaptureRectArea.CacheGreyMat, textRect)` | Yap | Submat of CacheGreyMat | **NOT disposed** — leaked if Yap path is taken |
| 303 | `TextInferenceFactory.Pick.Value.Inference(textMat)` | Yap | Submat of CacheGreyMat | Returns `string` |
| 307 | `using var textMat = new Mat(content.CaptureRectArea.SrcMat, textRect)` | Paddle | Submat of SrcMat | `using` — properly disposed |
| 308 | `TextRectExtractor.GetTextBoundingRect(textMat)` | Paddle | Submat of SrcMat | Pure function — no ownership |
| 314 | `using var textOnlyMat = new Mat(textMat, new Rect(...))` | Paddle | Submat of textMat | `using` — properly disposed |
| 316 | `OcrFactory.Paddle.OcrWithoutDetector(textOnlyMat)` | Paddle | Submat of textOnlyMat | Returns string |
| 337 | `OcrFactory.Paddle.Ocr(textMat)` | Paddle | Submat of SrcMat | Returns string |

**Note:** The Yap branch at line 302 creates `textMat` (a `new Mat(CacheGreyMat, textRect)`) WITHOUT `using`. This is a **Mat leak** — the submat holds a reference to the parent `CacheGreyMat` preventing GC. This is pre-existing upstream behavior, not introduced by extraction work.

---

## 2. Static Gateway Analysis

### 2.1 `OcrFactory.Paddle`

```csharp
// Core/Recognition/OCR/OcrFactory.cs:18
public static IOcrService Paddle =>
    App.ServiceProvider.GetRequiredService<OcrFactory>().PaddleOcr;
```

This is a **three-layer static gateway**:
1. `App.ServiceProvider` — static service locator
2. `GetRequiredService<OcrFactory>()` — resolves from DI
3. `.PaddleOcr` — lazy-init property on the resolved instance

**Statefulness:** `OcrFactory` has `_paddleOcrService` (lazy Paddle service), `_paddleModel` config, and `_gameCultureInfoName`. Once created, PaddleOcr is cached for the instance lifetime.

**Injection:** `OcrFactory` constructor accepts `ILogger<BgiOnnxFactory>` and `IOcrRuntimeConfigProvider`. It is registered in WPF DI at `App.xaml.cs` line 162:
```csharp
services.AddSingleton<OcrFactory>();
```

### 2.2 `TextInferenceFactory.Pick`

```csharp
// Core/Recognition/ONNX/SVTR/TextInferenceFactory.cs:9
public static readonly Lazy<ITextInference> Pick = new(() => Create(OcrEngineTypes.YapModel));
```

This is a **two-layer static gateway**:
1. Static `Lazy<ITextInference>` field — initialized once per AppDomain
2. Inside: `new PickTextInference()` — creates the concrete implementation

The `PickTextInference` constructor uses `App.ServiceProvider` internally to resolve `BgiOnnxFactory`:
```csharp
// (from source code, not visible in snippet above)
```

### 2.3 `TextRectExtractor.GetTextBoundingRect`

Pure static method — no state, no static gateway. It's a utility function that operates on a `Mat` and returns a `Rect`. This is fine as-is; no injection needed.

---

## 3. Proposed Interface Design

### 3.1 AutoPick-specific text recognizer

Rather than injecting the generic `IOcrService` (which has OCR/DET modes and engine abstractions), create a narrow interface that expresses exactly what AutoPickTrigger needs:

```csharp
namespace BetterGenshinImpact.Core.Recognition;

/// <summary>
/// AutoPick-specific text recognition.
/// Single method: recognize text from a greyscale image region.
/// </summary>
public interface IAutoPickTextRecognizer
{
    /// <summary>Recognize text from a greyscale Mat. Caller owns the Mat.</summary>
    string Recognize(Mat greyMat);
}
```

**Two implementations:**
- `PaddleAutoPickRecognizer` — wraps `OcrFactory.Paddle.OcrWithoutDetector`/`.Ocr`
- `YapAutoPickRecognizer` — wraps `TextInferenceFactory.Pick.Value.Inference`

**Engine selection** stays in `AutoPickTrigger.OnCapture` based on `config.OcrEngine`:
```csharp
private readonly IAutoPickTextRecognizer _paddleRecognizer;
private readonly IAutoPickTextRecognizer _yapRecognizer;

if (config.OcrEngine == nameof(PickOcrEngineEnum.Yap))
    text = _yapRecognizer.Recognize(textMat);
else
    text = _paddleRecognizer.Recognize(textMat);
```

### 3.2 Paddle-specific sub-paths kept in Paddle recognizer

The current Paddle path has two sub-branches:
1. Bounding rect found → `OcrWithoutDetector` (line 316)
2. Bounding rect not found → `Ocr` (line 337)

These are encapsulated inside `PaddleAutoPickRecognizer.Recognize()`. The trigger doesn't need to know about this internal routing.

### 3.3 TextRectExtractor stays as utility

`TextRectExtractor.GetTextBoundingRect` is a pure function — leave it as a static helper. The `PaddleAutoPickRecognizer` calls it internally.

---

## 4. Mat Leak Note (B9 scope boundary)

The Yap branch at line 302 creates:
```csharp
var textMat = new Mat(content.CaptureRectArea.CacheGreyMat, textRect);
```
without `using`. This leaks a `Mat` object each time the Yap branch executes.

**B9 does NOT fix this** — it's a pre-existing upstream issue. Document it in the audit for a future hygiene pass but do not change the allocation pattern. Mat lifecycle change belongs in a separate cleanup phase.

---

## 5. Construction Chain

| Caller | Current | B9 change |
|--------|---------|-----------|
| `AutoPickTrigger` ctor | Accesses `TextInferenceFactory.Pick` and `OcrFactory.Paddle` statically | Receives `IAutoPickTextRecognizer` for Paddle and Yap |
| `GameTaskManager.LoadInitialTriggers` | Windows — static factories resolve from DI | No change — wires recognizers into trigger ctor |
| `GameTaskManager.AddTrigger` | Same | Same |
| `MacAutoPickComposition.Compose` | Same (shim) | Same |
| Core shim `AddTrigger` | Same | Same |
| Tests | `TextInferenceFactory.Pick` may not work without ONNX models | Pass mock/recording recognizer |

---

## 6. macOS OCR Status

| Engine | C# Core availability | Notes |
|--------|---------------------|-------|
| PaddleOCR | **Unavailable** on macOS arm64 — native PaddleOcr binaries are Windows-only | Must be replaced or run outside process |
| Yap (SVTR) | **Unavailable** — PickTextInference depends on ONNX Runtime and model files not present on macOS | Could run ONNX on CPU but no model deployed |

**Current behavior on macOS:** Both OCR paths will throw at runtime if triggered (missing native libs / model files). The B9 extraction makes them injectable, so a macOS host can provide a stub/placeholder recognizer that returns empty text or logs.

**B9 does NOT implement a macOS OCR backend.** It only extracts the interface so macOS can provide one later.

---

## 7. Minimum B9 Implementation Scope

| Change | Files |
|--------|-------|
| Define `IAutoPickTextRecognizer` interface | New file in `Core/Abstractions/` |
| Create `PaddleAutoPickRecognizer : IAutoPickTextRecognizer` | `Core/Recognition/OCR/Paddle/` |
| Create `YapAutoPickRecognizer : IAutoPickTextRecognizer` | `Core/Recognition/ONNX/SVTR/` |
| AutoPickTrigger accepts `IAutoPickTextRecognizer paddle` + `IAutoPickTextRecognizer yap` in ctor | `AutoPickTrigger.cs` |
| Replace OcrFactory/TextInferenceFactory calls with recognizer.Recognize() | `AutoPickTrigger.cs` lines 303, 316, 337 |
| Windows DI registers recognizers | `App.xaml.cs` |
| MacAutoPickComposition passes recognizers | `MacAutoPickComposition.cs` |
| Verification tests pass mock recognizers | `Program.cs` |
| Core csproj includes new files | `.csproj` |

---

## 8. Out of Scope

| NOT in B9 | Reason |
|-----------|--------|
| Mat leak fix in Yap branch | Pre-existing upstream issue — document only |
| macOS OCR backend implementation | Requires platform-specific native work |
| AutoPickConfig/OcrEngine | B8.3 done — config read stays in trigger |
| Input / SystemInfo / RuntimeState | B8.1 / B8.2 / B8.3 done |
| Expand Core shim | B8.2 closeout — explicitly limited |
| Full WPF build | Manual/stage-closeout only |
| Shim deletion | B10 |
