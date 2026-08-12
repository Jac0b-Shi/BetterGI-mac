using System;
using System.Threading.Tasks;
using CsTrees;
using CsTrees.Visitors;
using Microsoft.Extensions.Logging;
using BetterGenshinImpact.GameTask.Model.Area;

namespace BetterGenshinImpact.GameTask.AutoFishing;

/// <summary>
/// CsTrees Visitor：在行为结束时自动截图。
/// 通过 Blackboard 获取当前帧，在行为的终态（Success/Failure）时保存截图。
/// </summary>
public class ScreenshotVisitor : VisitorBase
{
    private readonly ILogger _logger;

    public ScreenshotVisitor(ILogger logger) : base(full: false)
    {
        _logger = logger;
    }

    public override void Run(Behaviour behaviour)
    {
        if (behaviour.Status == Status.Running)
            return;

        if (behaviour is IScreenshotBehaviour screenshotBehaviour)
        {
            var currentFrame = screenshotBehaviour.Screenshot.Get();
            if (currentFrame == null)
                return;

            var fileName = $"{DateTime.Now:yyyyMMddHHmmssfff}_{behaviour.GetType().Name}_{behaviour.Status}.png";
            _logger.LogInformation("保存截图: {Name}", fileName);

            SaveScreenshot(currentFrame, fileName);
        }
    }

    public static void SaveScreenshot(ImageRegion imageRegion, string name)
    {
        if (String.IsNullOrWhiteSpace(name))
            name = $@"{DateTime.Now:yyyyMMddHHmmssffff}.png";
        AutoFishingRuntimePlatform.Current.SaveBehaviourScreenshot(imageRegion, name);
    }
}
