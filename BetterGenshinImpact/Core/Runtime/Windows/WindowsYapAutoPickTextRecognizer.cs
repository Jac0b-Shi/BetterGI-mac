using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Recognition.ONNX.SVTR;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Recognition.ONNX;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Runtime.Windows;

/// <summary>
/// Windows Yap (SVTR) OCR adapter for AutoPick text recognition.
/// Wraps the static TextInferenceFactory.Pick gateway — legacy Windows path.
/// </summary>
public sealed class WindowsYapAutoPickTextRecognizer(BgiOnnxFactory onnxFactory) : IYapAutoPickTextRecognizer
{
    private readonly ITextInference _inference = TextInferenceFactory.Create(OcrEngineTypes.YapModel, onnxFactory);

    public string Recognize(Mat textRegion)
    {
        return _inference.Inference(textRegion);
    }
}
