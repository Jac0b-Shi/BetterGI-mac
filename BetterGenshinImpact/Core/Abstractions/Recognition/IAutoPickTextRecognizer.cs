using OpenCvSharp;

namespace BetterGenshinImpact.Core.Abstractions.Recognition;

/// <summary>
/// Text region recognition for AutoPick.
/// Borrowed Mat — implementation must NOT dispose or retain the Mat.
/// Must complete all reading before returning.
/// </summary>
public interface IAutoPickTextRecognizer
{
    /// <param name="textRegion">
    /// Borrowed Mat region. Yap adapter expects greyscale;
    /// Paddle adapter expects source-color (BGR).
    /// </param>
    string Recognize(Mat textRegion);
}
