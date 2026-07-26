using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.AutoArtifactSalvage;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.GameTask.AutoStygianOnslaught;

public enum AutoStygianOnslaughtNotification
{
    Start,
    Reward,
    End,
}

public interface IAutoStygianOnslaughtRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    IOcrService OcrService { get; }
    string PickKey { get; }
    ILogger<AutoStygianOnslaughtTask> Logger { get; }
    void Notify(AutoStygianOnslaughtNotification notification, string message);
    Task RunArtifactSalvage(
        AutoArtifactSalvageTaskParam parameter, CancellationToken cancellationToken);
}
