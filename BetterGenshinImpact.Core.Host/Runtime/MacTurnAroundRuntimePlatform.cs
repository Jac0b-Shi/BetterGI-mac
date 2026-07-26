using BetterGenshinImpact.GameTask.Macro;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacTurnAroundRuntimePlatform(
    MacroSettingsCatalog settings,
    ForegroundInputCoordinator inputCoordinator,
    CancellationToken hostCancellationToken) : ITurnAroundRuntimePlatform
{
    public int RunaroundInterval => settings.Snapshot().RunaroundInterval;

    public int RunaroundMouseXInterval
    {
        get => settings.Snapshot().RunaroundMouseXInterval;
        set => settings.SetRunaroundMouseXInterval(value);
    }

    public void MoveMouseBy(
        int x,
        int y,
        CancellationToken cancellationToken) =>
        inputCoordinator.Dispatch(
            JObject.FromObject(new { action = "moveMouseBy", x, y }),
            cancellationToken);

    public void Wait(int milliseconds, CancellationToken cancellationToken)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            hostCancellationToken, cancellationToken);
        Task.Delay(milliseconds, linked.Token).GetAwaiter().GetResult();
    }
}
