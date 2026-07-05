using BetterGenshinImpact.Core.Abstractions.Recognition;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Adapters;

/// <summary>
/// Fail-fast placeholder for environments without a real Paddle OCR backend.
/// Never silently returns empty text — would mask missing wiring.
/// </summary>
public sealed class UnsupportedPaddleAutoPickTextRecognizer : IPaddleAutoPickTextRecognizer
{
    public string Recognize(Mat textRegion) =>
        throw new NotSupportedException(
            "AutoPick Paddle text recognition is not available on this platform. " +
            "Provide a real IPaddleAutoPickTextRecognizer implementation.");
}
