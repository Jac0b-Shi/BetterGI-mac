using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Recognition.OCR;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Adapters;

public sealed class PaddleAutoPickTextRecognizer(IOcrService ocrService) : IPaddleAutoPickTextRecognizer
{
    private readonly IOcrService _ocrService = ocrService ?? throw new ArgumentNullException(nameof(ocrService));

    public string Recognize(Mat textRegion)
    {
        ArgumentNullException.ThrowIfNull(textRegion);
        return _ocrService.OcrWithoutDetector(textRegion);
    }
}
