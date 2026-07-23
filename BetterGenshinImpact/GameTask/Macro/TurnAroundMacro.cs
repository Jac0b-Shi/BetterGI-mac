using System.Threading;

namespace BetterGenshinImpact.GameTask.Macro
{
    public class TurnAroundMacro
    {
        public static void Done(CancellationToken cancellationToken = default)
        {
            var platform = TurnAroundRuntimePlatform.Current;
            if (platform.RunaroundMouseXInterval == 0)
            {
                platform.RunaroundMouseXInterval = 1;
            }

            platform.MoveMouseBy(
                platform.RunaroundMouseXInterval,
                0,
                cancellationToken);
            platform.Wait(platform.RunaroundInterval, cancellationToken);
        }
    }
}
