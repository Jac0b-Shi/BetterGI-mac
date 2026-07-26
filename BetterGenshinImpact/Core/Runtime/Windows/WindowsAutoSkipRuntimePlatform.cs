using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.AutoSkip.Audio;
using BetterGenshinImpact.View.Windows;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Platform.Abstractions;
using BetterGenshinImpact.GameTask.Model.Area;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoSkipRuntimePlatform : IAutoSkipRuntimePlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public string PickKey => TaskContext.Instance().Config.AutoPickConfig.PickKey;
    public ILogger<T> GetLogger<T>() => App.GetLogger<T>();
    public IOcrService OcrService => OcrFactory.Paddle;
    public bool IsGameActive() => SystemControl.IsGenshinImpactActive();
    public void ActivateGameWindow() => SystemControl.ActivateWindow();
    public IAutoSkipAudioWaiter CreateAudioWaiter() => new DialogueOptionAudioWaiter(
        GetGameProcessId,
        processId => new ProcessLoopbackAudioCapture(processId));
    public void SimulateBackgroundAction(GIActions action) =>
        TaskContext.Instance().PostMessageSimulator.SimulateActionBackground(action);
    public void PressBackgroundKey(BgiKey key) =>
        TaskContext.Instance().PostMessageSimulator.KeyPressBackground(key.ToWindowsVirtualKey());
    public void BackgroundLeftButtonClick() =>
        TaskContext.Instance().PostMessageSimulator.LeftButtonClickBackground();
    public void BackgroundClick(Region region) => region.BackgroundClick();
    public void ReportError(string message) => ThemedMessageBox.Error(message);

    private static int? GetGameProcessId()
    {
        using var process = SystemControl.GetProcessByHandle(TaskContext.Instance().GameHandle);
        return process?.Id;
    }
}
