using BetterGenshinImpact.GameTask.AutoWood;
using BetterGenshinImpact.GameTask.AutoWood.Utils;
using System;
using Vanara.PInvoke;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoWoodRuntimePlatform : IAutoWoodRuntimePlatform
{
    public IDisposable AcquireSleepPrevention() => new SleepPreventionLease();

    public IAutoWoodLoginSession CreateLoginSession() => new Login3rdParty();

    private sealed class SleepPreventionLease : IDisposable
    {
        public SleepPreventionLease()
        {
            Kernel32.SetThreadExecutionState(
                Kernel32.EXECUTION_STATE.ES_CONTINUOUS |
                Kernel32.EXECUTION_STATE.ES_SYSTEM_REQUIRED |
                Kernel32.EXECUTION_STATE.ES_DISPLAY_REQUIRED);
        }

        public void Dispose() =>
            Kernel32.SetThreadExecutionState(Kernel32.EXECUTION_STATE.ES_CONTINUOUS);
    }
}
