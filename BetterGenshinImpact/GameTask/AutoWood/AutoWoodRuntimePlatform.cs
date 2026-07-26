using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.AutoWood;

public interface IAutoWoodLoginSession
{
    bool IsAvailable { get; }
    bool IsBilibili { get; }
    void RefreshAvailability();
    void Login(CancellationToken cancellationToken);
}

public interface IAutoWoodRuntimePlatform
{
    IDisposable AcquireSleepPrevention();
    IAutoWoodLoginSession CreateLoginSession();
}
