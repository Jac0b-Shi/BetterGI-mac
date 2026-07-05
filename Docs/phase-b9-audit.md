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

**Note:** The Yap branch at line 302 creates `textMat` (a `new Mat(CacheGreyMat, textRect)`) WITHOUT `using`. B9 must fix this as part of the ownership contract: the caller owns the Mat, so the Yap branch must use `using`. This does NOT change recognition behavior.

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

Interface in shared Core — no static gateway dependency:

```csharp
namespace BetterGenshinImpact.Core.Recognition;

/// <summary>
/// AutoPick-specific text region recognition.
/// Borrowed Mat — implementation must NOT dispose or retain the Mat.
/// Must complete all reading before returning.
/// </summary>
public interface IAutoPickTextRecognizer
{
    /// <param name="textRegion">Borrowed Mat region. Yap adapter expects greyscale;
    /// Paddle adapter expects source-color (BGR).</param>
    string Recognize(Mat textRegion);
}
```

**Two Windows legacy adapters** (bridge existing static gateways):

```csharp
// Windows adapter — wraps OcrFactory.Paddle
public sealed class WindowsPaddleAutoPickTextRecognizer : IAutoPickTextRecognizer
{
    public string Recognize(Mat textRegion)
    {
        // preserves existing OcrWithoutDetector/Ocr routing internally
        ...
    }
}

// Windows adapter — wraps TextInferenceFactory.Pick
public sealed class WindowsYapAutoPickTextRecognizer : IAutoPickTextRecognizer
{
    public string Recognize(Mat textRegion)
    {
        return TextInferenceFactory.Pick.Value.Inference(textRegion);
    }
}
```

These are Windows-specific adapters, NOT cross-platform Core implementations.
macOS composition replaces them with platform-appropriate implementations.

### 3.2 Engine selection stays in OnCapture

```csharp
if (config.OcrEngine == nameof(PickOcrEngineEnum.Yap))
    text = _yapRecognizer.Recognize(textMat);
else
    text = _paddleRecognizer.Recognize(textMat);
```

### 3.3 Paddle internal routing encapsulated

The current `OcrWithoutDetector` / `Ocr` branch is handled inside `WindowsPaddleAutoPickTextRecognizer`:
- If bounding rect found → `OcrWithoutDetector`
- Else → `Ocr`
- `TextRectExtractor.GetTextBoundingRect` called internally

### 3.4 TextRectExtractor stays as static utility

Pure function — no state, no static gateway, no injection needed.

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
| `AutoPickTrigger` ctor | No OCR initialization | Receives two required `IAutoPickTextRecognizer` dependencies |
| `AutoPickTrigger.OnCapture` | Static gateway calls (`OcrFactory.Paddle`, `TextInferenceFactory.Pick`) | Calls `_paddleRecognizer.Recognize()` / `_yapRecognizer.Recognize()` |
| `GameTaskManager.LoadInitialTriggers` | No change needed | Wires recognizers into trigger ctor |
| `GameTaskManager.AddTrigger` | Same | Same |
| `MacAutoPickComposition.Compose` | Same (shim path) | Same |
| Core shim `AddTrigger` | Same | Same |
| Tests | Static gateways may not work without models | Pass mock/recording recognizer |

---

## 6. macOS OCR Status

| Engine | macOS target status | Notes |
|--------|---------------------|-------|
| Paddle | **Not currently wired/verified** | Specific native runtime / NuGet RID support must be checked. The current Paddle OCR package/WinRT bridge may not distribute macOS arm64 binaries. |
| Yap (SVTR) | **Not currently wired/verified** | ONNX-based (`InferenceSession` is technically cross-platform), but blocked by: `App.ServiceProvider` coupling in `PickTextInference` constructor, lack of model file / dictionary deployment, and absence of composition wiring. |

**B9 does NOT implement a macOS OCR backend.** It only extracts the interface so macOS can provide one later via explicit composition, without touching static gateways.

Both engines share the same path forward: the macOS composition root must provide `IAutoPickTextRecognizer` instances that work on macOS — either by wrapping a cross-platform ONNX engine or by delegating to an external process.

---

## 7. Minimum B9 Implementation Scope

| Change | Files |
|--------|-------|
| Define `IAutoPickTextRecognizer` interface | New file in `Core/Abstractions/` |
| Create `WindowsPaddleAutoPickTextRecognizer : IAutoPickTextRecognizer` | `Core/Runtime/Windows/` |
| Create `WindowsYapAutoPickTextRecognizer : IAutoPickTextRecognizer` | `Core/Runtime/Windows/` |
| AutoPickTrigger accepts both recognizers as required ctor params | `AutoPickTrigger.cs` |
| Replace OcrFactory/TextInferenceFactory calls with recognizer.Recognize() | `AutoPickTrigger.cs` lines 300-337 |
| Yap branch: add `using` to `textMat` allocation (ownership fix) | `AutoPickTrigger.cs` line 302 |
| Windows DI registers recognizers | `App.xaml.cs` |
| MacAutoPickComposition passes recognizers (nullable macOS placeholders) | `MacAutoPickComposition.cs` |
| Verification tests pass recording/mock recognizers | `Program.cs` |

---

## 8. Out of Scope

| NOT in B9 | Reason |
|-----------|--------|
| macOS OCR backend implementation | Requires platform-specific native work — B9 only extracts interface |
| AutoPickConfig/OcrEngine | B8.3 done — config read stays in trigger |
| Input / SystemInfo / RuntimeState | B8.1 / B8.2 / B8.3 done |
| Expand Core shim | B8.2 closeout — explicitly limited |
| Full WPF build | Manual/stage-closeout only |
| Shim deletion | B10 |
