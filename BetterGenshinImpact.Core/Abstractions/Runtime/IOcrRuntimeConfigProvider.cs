using BetterGenshinImpact.Core.Recognition;

namespace BetterGenshinImpact.Core.Abstractions.Runtime;

/// <summary>
/// OCR runtime configuration.
/// Exposes only the values OcrFactory actually consumes —
/// not the full <c>OtherConfig.Ocr</c> ObservableObject (WPF data-binding baggage).
/// </summary>
public interface IOcrRuntimeConfigProvider
{
    /// <summary>PaddleOCR model selection strategy (version / detection model variant).</summary>
    PaddleOcrModelConfig PaddleModel { get; }

    /// <summary>Game culture info name for OCR language selection (e.g. "zh-Hans").</summary>
    string GameCultureInfoName { get; }
}
