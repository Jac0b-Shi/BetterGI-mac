using BetterGenshinImpact.Core.Simulator;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Macro;
using System.Threading;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsTurnAroundRuntimePlatform : ITurnAroundRuntimePlatform
{
    public int RunaroundInterval =>
        TaskContext.Instance().Config.MacroConfig.RunaroundInterval;

    public int RunaroundMouseXInterval
    {
        get => TaskContext.Instance().Config.MacroConfig.RunaroundMouseXInterval;
        set => TaskContext.Instance().Config.MacroConfig.RunaroundMouseXInterval = value;
    }

    public void MoveMouseBy(
        int x,
        int y,
        CancellationToken cancellationToken) =>
        Simulation.SendInput.Mouse.MoveMouseBy(x, y);

    public void Wait(int milliseconds, CancellationToken cancellationToken)
    {
        if (!cancellationToken.CanBeCanceled)
        {
            Thread.Sleep(milliseconds);
            return;
        }

        if (cancellationToken.WaitHandle.WaitOne(milliseconds))
            cancellationToken.ThrowIfCancellationRequested();
    }
}
