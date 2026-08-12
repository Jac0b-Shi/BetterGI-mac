using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition.ONNX;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Localization;
using Microsoft.Extensions.Logging;
using OpenCvSharp;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoFishingRuntimePlatform : IAutoFishingRuntimePlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public AutoFishingConfig Config => TaskContext.Instance().Config.AutoFishingConfig;
    public string GameCultureInfoName => TaskContext.Instance().Config.OtherConfig.GameCultureInfoName;
    public IOcrService OcrService => OcrFactory.Paddle;
    public ILogger<T> GetLogger<T>() => App.GetLogger<T>();
    public IStringLocalizer<T> GetStringLocalizer<T>() =>
        App.GetService<IStringLocalizer<T>>() ?? throw new InvalidOperationException(
            $"String localizer for {typeof(T).FullName} is not registered.");
    public BgiYoloPredictor CreateYoloPredictor(BgiOnnxModel model) =>
        App.ServiceProvider.GetRequiredService<BgiOnnxFactory>().CreateYoloPredictor(model);
    public bool IsGameActive(out string activeProcessName)
    {
        activeProcessName = SystemControl.GetActiveByProcess();
        return SystemControl.IsGenshinImpactActiveByProcess();
    }
    public ImageRegion? CaptureFrame() => TaskControl.CaptureToRectArea(forceNew: true);
    public void DisableRealtimeFishing() => Config.Enabled = false;
    public Task SetTimeAsync(int hour, int minute, CancellationToken cancellationToken) =>
        new SetTimeTask().Start(hour, minute, cancellationToken);

    public void SaveBehaviourScreenshot(ImageRegion imageRegion, string fileName)
    {
        var savePath = Global.Absolute(@$"log\screenshot\{fileName}");
        var copy = imageRegion.SrcMat.Clone();
        var coverUid = TaskContext.Instance().Config.CommonConfig.ScreenshotUidCoverEnabled;
        var assetScale = TaskContext.Instance().SystemInfo.ScaleTo1080PRatio;
        _ = Task.Run(() =>
        {
            using (copy)
            {
                if (coverUid)
                    ScreenshotPrivacy.ApplyUidCover(copy, assetScale);
                Cv2.ImWrite(savePath, copy);
            }
        });
    }
}
