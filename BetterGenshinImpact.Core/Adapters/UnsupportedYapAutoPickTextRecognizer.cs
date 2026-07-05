using BetterGenshinImpact.Core.Abstractions.Recognition;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Adapters;

/// <summary>
/// Fail-fast placeholder for environments without a real Yap (SVTR) backend.
/// Never silently returns empty text — would mask missing wiring.
/// </summary>
public sealed class UnsupportedYapAutoPickTextRecognizer : IYapAutoPickTextRecognizer
{
    public string Recognize(Mat textRegion) =>
        throw new NotSupportedException(
            "AutoPick Yap (SVTR) text recognition is not available on this platform. " +
            "Provide a real IYapAutoPickTextRecognizer implementation.");
}
