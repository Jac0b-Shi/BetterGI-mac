using BetterGenshinImpact.GameTask.AutoWood;
using System.Diagnostics;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoWoodRuntimePlatform : IAutoWoodRuntimePlatform
{
    public IDisposable AcquireSleepPrevention() => new CaffeinateLease();

    public IAutoWoodLoginSession CreateLoginSession() => NoThirdPartyLoginSession.Instance;

    private sealed class CaffeinateLease : IDisposable
    {
        private readonly Process _process;

        public CaffeinateLease()
        {
            var startInfo = new ProcessStartInfo("/usr/bin/caffeinate")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            startInfo.ArgumentList.Add("-dims");
            startInfo.ArgumentList.Add("-w");
            startInfo.ArgumentList.Add(Environment.ProcessId.ToString());
            _process = Process.Start(startInfo)
                ?? throw new InvalidOperationException("Unable to start macOS caffeinate for AutoWood.");
        }

        public void Dispose()
        {
            if (!_process.HasExited)
            {
                _process.Kill();
                _process.WaitForExit();
            }
            _process.Dispose();
        }
    }

    private sealed class NoThirdPartyLoginSession : IAutoWoodLoginSession
    {
        public static NoThirdPartyLoginSession Instance { get; } = new();
        public bool IsAvailable => false;
        public bool IsBilibili => false;
        public void RefreshAvailability() { }
        public void Login(CancellationToken cancellationToken) { }
    }
}
