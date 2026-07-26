using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Recognition;

namespace BetterGenshinImpact.Core.Runtime.Windows;

/// <summary>
/// Windows implementation of <see cref="IOcrRuntimeConfigProvider"/>.
/// Delegates to the real upstream <see cref="GameTask.TaskContext"/> at each access.
/// <c>PaddleModel</c> and <c>GameCultureInfoName</c> are read dynamically — no caching.
/// </summary>
public sealed class WindowsOcrRuntimeConfigProvider : IOcrRuntimeConfigProvider
{
    public PaddleOcrModelConfig PaddleModel =>
        GameTask.TaskContext.Instance().Config.OtherConfig.OcrConfig.PaddleOcrModelConfig;

    public string GameCultureInfoName =>
        GameTask.TaskContext.Instance().Config.OtherConfig.GameCultureInfoName;
}
