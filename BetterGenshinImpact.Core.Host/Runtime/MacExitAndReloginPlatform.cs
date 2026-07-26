using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Job;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacExitAndReloginPlatform : IExitAndReloginPlatform
{
    public void FocusGameWindow() => TaskControlPlatform.Current.EnsureGameActive();

    // The macOS game distribution has no YuanShen channel=14/Bilibili login window.
    public bool TryLoginThirdParty(CancellationToken cancellationToken) => false;
}
