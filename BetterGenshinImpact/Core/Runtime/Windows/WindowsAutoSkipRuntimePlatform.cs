using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoSkip;
using BetterGenshinImpact.GameTask.AutoSkip.Audio;
using BetterGenshinImpact.View.Windows;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoSkipRuntimePlatform : IAutoSkipRuntimePlatform
{
    public IAutoSkipAudioWaiter CreateAudioWaiter() => new DialogueOptionAudioWaiter();
    public void SimulateBackgroundAction(GIActions action) =>
        TaskContext.Instance().PostMessageSimulator.SimulateActionBackground(action);
    public void PressBackgroundKey(int windowsVirtualKey) =>
        TaskContext.Instance().PostMessageSimulator.KeyPressBackground((Vanara.PInvoke.User32.VK)windowsVirtualKey);
    public void BackgroundLeftButtonClick() =>
        TaskContext.Instance().PostMessageSimulator.LeftButtonClickBackground();
    public void ReportError(string message) => ThemedMessageBox.Error(message);
}
