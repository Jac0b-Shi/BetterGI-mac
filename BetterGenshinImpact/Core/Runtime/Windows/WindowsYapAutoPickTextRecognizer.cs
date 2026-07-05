using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Recognition.ONNX.SVTR;
using BetterGenshinImpact.Core.Recognition;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Runtime.Windows;

/// <summary>
/// Windows Yap (SVTR) OCR adapter for AutoPick text recognition.
/// Wraps the static TextInferenceFactory.Pick gateway — legacy Windows path.
/// </summary>
public sealed class WindowsYapAutoPickTextRecognizer : IYapAutoPickTextRecognizer
{
    public string Recognize(Mat textRegion)
    {
        return TextInferenceFactory.Pick.Value.Inference(textRegion);
    }
}
