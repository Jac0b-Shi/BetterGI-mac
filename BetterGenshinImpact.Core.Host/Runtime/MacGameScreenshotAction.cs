using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask.Screenshot;
using Microsoft.Extensions.Logging;
using OpenCvSharp;
using System.Runtime.Versioning;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public interface IGameScreenshotAction
{
    string TakeScreenshot(CancellationToken cancellationToken);
}

[SupportedOSPlatform("macos")]
public sealed class MacGameScreenshotAction(
    RuntimeLayout layout,
    PlatformCallbackChannel callbacks,
    string sessionToken,
    SharedCaptureRingReader captureRing,
    Func<double> scaleTo1080PRatio,
    ILogger<GameScreenshotTask> logger) : IGameScreenshotAction
{
    public string TakeScreenshot(CancellationToken cancellationToken) =>
        new GameScreenshotTask(
                new RuntimePlatform(
                    layout, callbacks, sessionToken, captureRing,
                    scaleTo1080PRatio, cancellationToken),
                logger)
            .TakeScreenshot();

    private sealed class RuntimePlatform(
        RuntimeLayout layout,
        PlatformCallbackChannel callbacks,
        string sessionToken,
        SharedCaptureRingReader captureRing,
        Func<double> scaleTo1080PRatio,
        CancellationToken cancellationToken) : IGameScreenshotRuntimePlatform
    {
        public string ScreenshotDirectory =>
            Path.Combine(layout.LogPath, "screenshot");

        public bool ScreenshotUidCoverEnabled =>
            LoadScreenshotUidCoverEnabled(layout);

        public double ScaleTo1080PRatio => scaleTo1080PRatio();

        public Mat Capture()
        {
            var response = callbacks.InvokeAsync(
                    "capture.request", null, sessionToken, cancellationToken)
                .GetAwaiter().GetResult()
                ?? throw new InvalidDataException(
                    "capture.request returned an empty response.");
            using var region = captureRing.Read(response);
            return region.SrcMat.Clone();
        }
    }

    private static bool LoadScreenshotUidCoverEnabled(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path))
            return true;
        var root = JsonNode.Parse(
            File.ReadAllText(path),
            documentOptions: new JsonDocumentOptions
            {
                AllowTrailingCommas = true,
                CommentHandling = JsonCommentHandling.Skip,
            }) as JsonObject
            ?? throw new InvalidDataException(
                "User/config.json root must be an object.");
        return root["commonConfig"]?["screenshotUidCoverEnabled"]
            ?.GetValue<bool>() ?? true;
    }
}
