using BetterGenshinImpact.Core.Simulator;
using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoEat;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoEatRuntimePlatform : IAutoEatRuntimePlatform
{
    public AutoEatConfig Config => TaskContext.Instance().Config.AutoEatConfig;
    public ILogger<T> GetLogger<T>() => App.GetLogger<T>();
    public void SimulateAction(GIActions action) => Simulation.SendInput.SimulateAction(action);
}
