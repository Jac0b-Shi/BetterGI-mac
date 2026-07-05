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

### 3.1 AutoPick-specific text recognizer — role interfaces

Two DI-distinguishable role interfaces sharing a common contract.
This prevents the composition root from passing Paddle where Yap is expected and vice versa.

Interface in shared Core — no static gateway dependency:

```csharp
namespace BetterGenshinImpact.Core.Recognition;

/// <summary>Text region recognition — borrowed Mat, caller owns it.</summary>
public interface IAutoPickTextRecognizer
{
    /// <param name="textRegion">Borrowed Mat region. Yap adapter expects greyscale;
    /// Paddle adapter expects source-color (BGR).</param>
    string Recognize(Mat textRegion);
}

/// <summary>DI-role for the Paddle OCR recognizer.</summary>
public interface IPaddleAutoPickTextRecognizer : IAutoPickTextRecognizer { }

/// <summary>DI-role for the Yap (SVTR) recognizer.</summary>
public interface IYapAutoPickTextRecognizer : IAutoPickTextRecognizer { }
```

Windows adapters implement the corresponding role interface:

```csharp
public sealed class WindowsPaddleAutoPickTextRecognizer
    : IPaddleAutoPickTextRecognizer
{
    public string Recognize(Mat textRegion) { /* ... */ }
}

public sealed class WindowsYapAutoPickTextRecognizer
    : IYapAutoPickTextRecognizer
{
    public string Recognize(Mat textRegion) { /* ... */ }
}
```

These are **Windows-specific adapters**, only compiled into the full WPF target
(`BetterGenshinImpact.csproj` — `net8.0-windows10.0.22621.0`).
They are NOT compiled into the cross-platform Core target (`BetterGenshinImpact.Core.csproj` — `net8.0`).
macOS composition provides different implementations (see §6).

Both recognizers are **required, non-nullable** constructor parameters using their role types:

```csharp
public AutoPickTrigger(
    ...,
    IPaddleAutoPickTextRecognizer paddleRecognizer,
    IYapAutoPickTextRecognizer yapRecognizer)
```

No `IAutoPickTextRecognizer?`, no null fallback, no static gateway fallback in the trigger.
Microsoft.Extensions.DependencyInjection resolves unambiguously because the two role types are different.

For composition roots that lack a real backend:

```csharp
public sealed class UnsupportedPaddleAutoPickTextRecognizer
    : IPaddleAutoPickTextRecognizer
{
    private readonly string _engineName = "Paddle";
    public string Recognize(Mat textRegion) =>
        throw new NotSupportedException(
            "AutoPick Paddle text recognition is not available on this platform.");
}

public sealed class UnsupportedYapAutoPickTextRecognizer
    : IYapAutoPickTextRecognizer
{
    private readonly string _engineName = "Yap";
    public string Recognize(Mat textRegion) =>
        throw new NotSupportedException(
            "AutoPick Yap text recognition is not available on this platform.");
}
```

Use these in `MacAutoPickComposition` until real macOS OCR backends exist.

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

### 3.5 Paddle routing — behavioral equivalence constraints

When moving the Paddle OCR routing into `WindowsPaddleAutoPickTextRecognizer`, the following must be preserved identically:

| Element | Constraint |
|---------|-----------|
| `TextRectExtractor.GetTextBoundingRect` | Called on full color `textRegion` — same as current `SrcMat` submat |
| `boundingRect.X < 20` | Condition unchanged |
| `boundingRect.Width > 5` | Condition unchanged |
| `boundingRect.Height > 5` | Condition unchanged |
| `textOnlyMat` crop formula | `new Rect(0, 0, boundingRect.Right + 5 < textMat.Width ? boundingRect.Right + 5 : textMat.Width, textMat.Height)` — exact |
| `OcrWithoutDetector` | Called when bounding rect is valid |
| Fallback `Ocr` | Called when bounding rect is invalid; debug message `"-- 无法识别到有效文字区域，尝试直接OCR DET"` preserved |
| Mat disposal | `using var textMat`, `using var textOnlyMat` — same disposal pattern |
| Returns | Raw OCR string — `ProcessOcrText` remains in trigger, not in adapter |

### 3.8 Engine selection — two-branch dispatch stays in trigger

The `config.OcrEngine` comparison and dispatch remains in `AutoPickTrigger.OnCapture`.
Exactly one recognizer is invoked per frame — never both:

```csharp
if (config.OcrEngine == nameof(PickOcrEngineEnum.Yap))
    text = _yapRecognizer.Recognize(textMat);
else
    text = _paddleRecognizer.Recognize(textMat);
```

### 3.7 TextRectExtractor stays as static utility

`TextRectExtractor.GetTextBoundingRect` is a pure function — no state, no static gateway, no injection needed. It remains a static utility called inside `WindowsPaddleAutoPickTextRecognizer`.

---

## 4. Yap Mat Dispose — B9 Scope

The Yap branch at line 302 creates:
```csharp
var textMat = new Mat(content.CaptureRectArea.CacheGreyMat, textRect);
```
without `using`. B9 fixes this as part of the ownership contract change:
```csharp
using var textMat = new Mat(content.CaptureRectArea.CacheGreyMat, textRect);
text = _yapRecognizer.Recognize(textMat);
```
This does NOT change recognition behavior. It only ensures the submat is released when
the scope exits. This is a necessary part of moving ownership to the recognizer contract.

---

## 5. Construction Chain

| Caller | Current | B9 change |
|--------|---------|-----------|
| `AutoPickTrigger` ctor | No OCR initialization | Receives `IPaddleAutoPickTextRecognizer` + `IYapAutoPickTextRecognizer` |
| `AutoPickTrigger.OnCapture` | Static gateways (`OcrFactory.Paddle`, `TextInferenceFactory.Pick`) | Calls `_paddleRecognizer.Recognize()` / `_yapRecognizer.Recognize()` |
| Windows DI (`App.xaml.cs`) | — | Registers `IPaddleAutoPickTextRecognizer` and `IYapAutoPickTextRecognizer` (unambiguous types) |
| `TaskTriggerDispatcher` ctor | Receives configProvider + inputBackend | **New:** receives both role-typed recognizers from DI |
| `TaskTriggerDispatcher.Start` → `GameTaskManager.LoadInitialTriggers` | Forwards inputBackend + systemInfo + configProvider | **New:** forwards both recognizers (role-typed params) |
| `TaskTriggerDispatcher.AddTrigger` → `GameTaskManager.AddTrigger` | Forwards inputBackend + systemInfo + configProvider | **New:** forwards both recognizers |
| `MacAutoPickComposition.Compose` | Forwards configProvider + state + backend + systemInfo | **New:** receives both recognizers from macOS host; forwards to trigger |
| Core shim `AddTrigger` | Forwards inputBackend + systemInfo + configProvider | **New:** forwards both recognizers |
| Tests | Static gateways may not work | Pass `FakePaddleRecognizer` and `FakeYapRecognizer` (different marker instances) |

**Constraints on GameTaskManager:**
- Must NOT `new WindowsPaddle...()` or `new WindowsYap...()` directly
- Must NOT access `App.ServiceProvider`
- Receives both recognizers via explicit method parameters from the caller

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
| Define role interfaces (`IAutoPickTextRecognizer`, `IPaddleAutoPickTextRecognizer`, `IYapAutoPickTextRecognizer`) | Shared Core abstraction — `BetterGenshinImpact.Core/Abstractions/` |
| Create `WindowsPaddleAutoPickTextRecognizer : IPaddleAutoPickTextRecognizer` | WPF project only — `BetterGenshinImpact/Core/Runtime/Windows/` |
| Create `WindowsYapAutoPickTextRecognizer : IYapAutoPickTextRecognizer` | WPF project only — same directory |
| Create `UnsupportedPaddleAutoPickTextRecognizer : IPaddleAutoPickTextRecognizer` | Core — macOS composition placeholder |
| Create `UnsupportedYapAutoPickTextRecognizer : IYapAutoPickTextRecognizer` | Core — macOS composition placeholder |
| AutoPickTrigger accepts both as required non-nullable role-typed params | `AutoPickTrigger.cs` |
| Yap branch: `using var textMat` (ownership fix) | `AutoPickTrigger.cs` line 302 |
| Replace OcrFactory/TextInferenceFactory calls | `AutoPickTrigger.cs` |
| Windows DI: register `IPaddleAutoPickTextRecognizer` + `IYapAutoPickTextRecognizer` | `App.xaml.cs` |
| TaskTriggerDispatcher receives + forwards both role-typed recognizers | `TaskTriggerDispatcher.cs` |
| GameTaskManager.LoadInitialTriggers accepts + forwards both | `GameTaskManager.cs` |
| GameTaskManager.AddTrigger accepts + forwards both | `GameTaskManager.cs` |
| Core shim AddTrigger accepts + forwards both | `Shim/GameTaskManager.cs` |
| MacAutoPickComposition receives + forwards both (Unsupported placeholders) | `MacAutoPickComposition.cs` |
| Verification tests pass `FakePaddleRecognizer` + `FakeYapRecognizer` | `Program.cs` |

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
