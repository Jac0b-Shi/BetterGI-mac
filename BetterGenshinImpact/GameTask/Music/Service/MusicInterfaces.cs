using BetterGenshinImpact.GameTask.Music.Model;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Threading;
using System.Threading.Tasks;
#if WINDOWS
using System.Windows.Media;
#endif

namespace BetterGenshinImpact.GameTask.Music.Service;

public interface IMusicScoreParser
{
    bool CanParse(string path);

    Task<PerformanceScore> ParseAsync(string path, string rootFolder, CancellationToken cancellationToken);
}

public interface IMusicLibraryService : IDisposable
{
    event EventHandler? FilesChanged;

    event EventHandler<MusicScoreParseFailedEventArgs>? ScoreParseFailed;

    Task<IReadOnlyList<PerformanceScore>> ScanAsync(string rootFolder, CancellationToken cancellationToken);

    void Watch(string rootFolder);
}

public sealed class MusicScoreParseFailedEventArgs(string filePath, string errorMessage) : EventArgs
{
    public string FilePath { get; } = filePath;

    public string ErrorMessage { get; } = errorMessage;
}

#if WINDOWS
public interface IMusicCoverService
{
    Task<ImageSource?> GetCoverAsync(string songName, CancellationToken cancellationToken);
}
#endif

public interface IInstrumentProfileService
{
    ObservableCollection<InstrumentProfile> Profiles { get; }

    InstrumentProfile StandardProfile { get; }

    InstrumentProfile Find(string? name);

    void Save();
}

public interface IMusicTimelineBuilder
{
    PerformanceTimeline Build(
        PerformanceScore score,
        InstrumentProfile outputProfile,
        int transpose);
}

public interface IKeyInputTransport
{
    MusicInputMode Mode { get; }

    void KeyDown(char key);

    void KeyUp(char key);

    void ReleaseAll();

    void DispatchBatch(
        IReadOnlyList<PerformanceEvent> events,
        int startIndex,
        int count);
}

public interface IMusicPlaybackGate
{
    bool IsAvailable(CancellationToken cancellationToken);

    Task WaitUntilAvailableAsync(CancellationToken cancellationToken);
}

public sealed class MusicInputUnavailableException : InvalidOperationException
{
    public MusicInputUnavailableException()
        : base("Music input is temporarily unavailable.")
    {
    }

    public MusicInputUnavailableException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

public enum MusicPlaybackCompletionReason
{
    NaturalCompletion,
    ExplicitStop,
    Cancelled
}

public sealed class MusicPlaybackEndedEventArgs(
    MusicPlaybackCompletionReason reason,
    int queueIndex,
    TimeSpan position) : EventArgs
{
    public MusicPlaybackCompletionReason Reason { get; } = reason;

    public int QueueIndex { get; } = queueIndex;

    public TimeSpan Position { get; } = position;
}

public interface IMusicPlaybackService
{
    event EventHandler<PlaybackSnapshot>? SnapshotChanged;

    event EventHandler<MusicPlaybackEndedEventArgs>? PlaybackEnded;

    PlaybackSnapshot Snapshot { get; }

    Task RunPlaylistAsync(
        IReadOnlyList<PerformanceScore> queue,
        int startIndex,
        MusicPlaybackOptions options,
        CancellationToken cancellationToken);

    void Pause();

    void Resume();

    void Stop();

    void Next();

    void Previous();

    void Seek(TimeSpan position);

    void SetSpeed(double speed);

    void SetPlaybackMode(MusicPlaybackMode mode);
}

public interface IMusicStateStore
{
    MusicLibraryState State { get; }

    void Save();
}
