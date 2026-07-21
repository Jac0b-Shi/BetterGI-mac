using BetterGenshinImpact.GameTask.Common.Job;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsCraftMaterialRuntimePlatform : ICraftMaterialRuntimePlatform
{
    public ILogger<CraftMaterialTask> Logger => App.GetLogger<CraftMaterialTask>();
}
