using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.GameTask.AutoPick;

namespace BetterGenshinImpact.Core.Runtime.Windows;

/// <summary>
/// Windows implementation of <see cref="IAutoPickConfigProvider"/>.
/// Delegates to the real upstream <see cref="GameTask.TaskContext"/> at each access.
/// Does NOT cache <c>AutoPickConfig</c> — ensures config reloads are reflected.
/// </summary>
public sealed class WindowsAutoPickConfigProvider : IAutoPickConfigProvider
{
    public AutoPickConfig AutoPickConfig => GameTask.TaskContext.Instance().Config.AutoPickConfig;
}
