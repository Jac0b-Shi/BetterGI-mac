using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model.Area;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoFishingRuntimePlatform : IAutoFishingRuntimePlatform
{
    public void SaveBehaviourScreenshot(ImageRegion imageRegion, string fileName) =>
        throw new CapabilityUnavailableException(
            "AutoFishing behavior screenshots require the Core-owned UID-cover configuration to be composed.");
}
