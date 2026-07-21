using BetterGenshinImpact.GameTask.Common.Job;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacCraftMaterialRuntimePlatform(
    ILogger<CraftMaterialTask> logger) : ICraftMaterialRuntimePlatform
{
    public ILogger<CraftMaterialTask> Logger { get; } = logger ?? throw new ArgumentNullException(nameof(logger));
}
