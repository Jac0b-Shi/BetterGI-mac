using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Recognition.ONNX.SVTR;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Adapters;

public sealed class YapAutoPickTextRecognizer(ITextInference inference) : IYapAutoPickTextRecognizer
{
    private readonly ITextInference _inference = inference ?? throw new ArgumentNullException(nameof(inference));

    public string Recognize(Mat textRegion)
    {
        ArgumentNullException.ThrowIfNull(textRegion);
        return _inference.Inference(textRegion);
    }
}
