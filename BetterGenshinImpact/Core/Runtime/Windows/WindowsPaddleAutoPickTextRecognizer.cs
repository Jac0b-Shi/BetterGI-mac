using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.AutoPick;
using OpenCvSharp;
using System.Diagnostics;

namespace BetterGenshinImpact.Core.Runtime.Windows;

/// <summary>
/// Windows Paddle OCR adapter for AutoPick text recognition.
/// Encapsulates the existing bounding-rect extraction + OcrWithoutDetector / Ocr routing.
/// Wraps the static OcrFactory.Paddle gateway — legacy Windows path.
/// </summary>
public sealed class WindowsPaddleAutoPickTextRecognizer : IPaddleAutoPickTextRecognizer
{
    public string Recognize(Mat textRegion)
    {
        var boundingRect = TextRectExtractor.GetTextBoundingRect(textRegion);

        if (boundingRect.X < 20 && boundingRect.Width > 5 && boundingRect.Height > 5)
        {
            using var textOnlyMat = new Mat(textRegion, new Rect(0, 0,
                boundingRect.Right + 5 < textRegion.Width
                    ? boundingRect.Right + 5
                    : textRegion.Width,
                textRegion.Height));
            return OcrFactory.Paddle.OcrWithoutDetector(textOnlyMat);
        }

        Debug.WriteLine("-- 无法识别到有效文字区域，尝试直接OCR DET");
        return OcrFactory.Paddle.Ocr(textRegion);
    }
}
