using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.GameTask;
using CommunityToolkit.Mvvm.Messaging;
using CommunityToolkit.Mvvm.Messaging.Messages;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition.OCR;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsPathExecutorPlatform : IPathExecutorPlatform
{
    public (int Width, int Height) GetGameScreenSize()
    {
        var size = SystemControl.GetGameScreenRect(TaskContext.Instance().GameHandle);
        return (size.Width, size.Height);
    }

    public void PublishCurrentPathing(PathingTask task) =>
        WeakReferenceMessenger.Default.Send(new PropertyChangedMessage<object>(
            this, "UpdateCurrentPathing", new object(), task));

    public string AutoFetchDispatchAdventurersGuildCountry =>
        TaskContext.Instance().Config.OtherConfig.AutoFetchDispatchAdventurersGuildCountry;
    public PathingConditionConfig PathingConditionConfig => TaskContext.Instance().Config.PathingConditionConfig;
    public IOcrService OcrService => OcrFactory.Paddle;
}
