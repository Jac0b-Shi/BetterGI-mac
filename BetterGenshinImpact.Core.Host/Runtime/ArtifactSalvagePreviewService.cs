using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.AutoArtifactSalvage;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class ArtifactSalvagePreviewService(
    IOcrService ocrService,
    Func<ISystemInfo> systemInfo,
    ILogger<AutoArtifactSalvageTask> logger)
{
    public async Task<object> CaptureAsync(
        string javaScript,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        using var frame = TaskControl.CaptureToRectArea(forceNew: true);
        using var card = frame.DeriveCrop(new Rect(
            (int)(frame.Width * 0.70),
            (int)(frame.Height * 0.112),
            (int)(frame.Width * 0.275),
            (int)(frame.Height * 0.50)));
        if (!Cv2.ImEncode(".png", card.SrcMat, out var encoded))
            throw new IOException("OpenCV failed to encode the artifact preview.");

        var task = new AutoArtifactSalvageTask(
            new AutoArtifactSalvageTaskParam(5, javaScript, null, null, null),
            ocrService,
            systemInfo().AssetScale,
            logger);
        var artifact = task.GetArtifactStat(card.SrcMat, ocrService, out var recognizedText);
        var isMatch = await AutoArtifactSalvageTask.IsMatchJavaScript(
            artifact, javaScript, logger);
        cancellationToken.ThrowIfCancellationRequested();
        return new
        {
            imagePngBase64 = Convert.ToBase64String(encoded),
            recognizedText,
            structuredResult = artifact.ToStructuredString(),
            isMatch,
        };
    }
}
