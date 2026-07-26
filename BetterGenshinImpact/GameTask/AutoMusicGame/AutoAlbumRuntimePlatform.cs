using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.GameTask.AutoMusicGame;

public enum AutoAlbumNotification
{
    Start,
    End,
    Error,
}

public interface IAutoAlbumRuntimePlatform
{
    ISystemInfo SystemInfo { get; }
    bool PropagateTaskExceptions { get; }
    ILogger<AutoAlbumTask> Logger { get; }
    void Notify(
        AutoAlbumNotification notification, string message,
        System.Exception? exception = null);
}
