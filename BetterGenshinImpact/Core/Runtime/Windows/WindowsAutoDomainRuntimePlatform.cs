using System;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.GameTask.AutoDomain;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.Common.Map;
using NotifyService = BetterGenshinImpact.Service.Notification.Notify;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Localization;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoDomainRuntimePlatform : IAutoDomainRuntimePlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public IOcrService OcrService => OcrFactory.Paddle;
    public IStringLocalizer<AutoDomainTask> StringLocalizer =>
        App.GetService<IStringLocalizer<AutoDomainTask>>()
        ?? throw new InvalidOperationException("AutoDomain localizer is unavailable.");
    public ILogger<AutoDomainTask> Logger => App.GetLogger<AutoDomainTask>();

    public BgiYoloPredictor CreateTreePredictor() => App.ServiceProvider
        .GetRequiredService<BgiOnnxFactory>().CreateYoloPredictor(BgiOnnxModel.BgiTree);

    public void DrawCameraDirection(ImageRegion region, double angle) =>
        CameraOrientation.DrawDirection(region, angle);

    public void AddAutoEatTrigger() => TaskTriggerDispatcher.Instance().AddTrigger("AutoEat", null);

    public void Notify(AutoDomainNotification notification, string message)
    {
        var eventType = notification switch
        {
            AutoDomainNotification.Start => NotificationEvent.DomainStart,
            AutoDomainNotification.Retry => NotificationEvent.DomainRetry,
            AutoDomainNotification.Reward => NotificationEvent.DomainReward,
            AutoDomainNotification.End => NotificationEvent.DomainEnd,
            _ => throw new ArgumentOutOfRangeException(nameof(notification)),
        };
        if (notification == AutoDomainNotification.Retry)
            NotifyService.Event(eventType).Error(message);
        else
            NotifyService.Event(eventType).Success(message);
    }
}
