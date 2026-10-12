using BetterGenshinImpact.Core.Input;
using BetterGenshinImpact.Core.Simulator;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoPick;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.GameTask.Model;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsBvSimpleOperationPlatform : IBvSimpleOperationPlatform
{
    public ISystemInfo SystemInfo => TaskContext.Instance().SystemInfo;
    public AutoPickConfig AutoPickConfig => TaskContext.Instance().Config.AutoPickConfig;
    public void PressPickKey() => InputHub.Foreground.SimulateAction(
        Core.Simulator.Extensions.GIActions.PickUpOrInteract);
}
