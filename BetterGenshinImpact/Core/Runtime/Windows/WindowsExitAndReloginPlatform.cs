using BetterGenshinImpact.GameTask.AutoWood.Utils;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask;
using System.Threading;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsExitAndReloginPlatform : IExitAndReloginPlatform
{
    private readonly Login3rdParty _login3rdParty = new();

    public void FocusGameWindow() => SystemControl.FocusWindow(TaskContext.Instance().GameHandle);

    public bool TryLoginThirdParty(CancellationToken cancellationToken)
    {
        _login3rdParty.RefreshAvailabled();
        if (_login3rdParty is not
            { Type: Login3rdParty.The3rdPartyType.Bilibili, IsAvailabled: true })
            return false;

        Thread.Sleep(100);
        _login3rdParty.Login(cancellationToken);
        return true;
    }
}
