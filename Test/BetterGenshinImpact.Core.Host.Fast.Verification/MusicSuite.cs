using BetterGenshinImpact.GameTask.Music.Model;
using BetterGenshinImpact.GameTask.Music.Service;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Verification.Framework;
using System.Collections.ObjectModel;
using System.Diagnostics;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class MusicSuite : IVerificationSuite
{
    public string Name => "music";

    public async Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var root = Path.Combine(
            Path.GetTempPath(), $"bettergi-music-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            var scorePath = Path.Combine(root, "keyboard.json");
            await File.WriteAllTextAsync(
                scorePath,
                """
                {
                  "type": "keyboard",
                  "name": "contract",
                  "instrument": "test",
                  "bpm": 120,
                  "notes": "QW"
                }
                """,
                cancellationToken);
            var score = await new MusicScoreParser().ParseAsync(
                scorePath, root, cancellationToken);
            context.Require(
                score.IsValid &&
                score.SourceTimeline.Events.Count == 4 &&
                score.SourceTimeline.Events[0] == new PerformanceEvent(
                    TimeSpan.Zero, 'Q', PerformanceEventType.KeyDown) &&
                score.SourceTimeline.Duration == TimeSpan.FromSeconds(1),
                "Portable music parser did not preserve the keyboard score timeline.");

            var profile = new InstrumentProfile
            {
                Name = "test",
                Mappings = new ObservableCollection<InstrumentKeyMapping>
                {
                    new('Q', 60),
                    new('W', 62),
                },
            };
            var timeline = new MusicTimelineBuilder(
                new FixedProfileService(profile)).Build(score, profile, 0);
            context.Require(
                timeline.Events.Count == 4 && score.PlayableRatio == 1,
                "Portable music timeline mapping did not retain all playable notes.");

            var transport = new RecordingTransport();
            transport.KeyDown('q');
            transport.KeyDown('Q');
            transport.KeyUp('Q');
            transport.KeyUp('Q');
            transport.KeyDown('W');
            transport.ReleaseAll();
            context.Require(
                transport.Events.SequenceEqual(
                    new[] { "down:Q", "up:Q", "down:W", "up:W" }),
                "Music input transport did not deduplicate key edges or release held keys.");
            context.Require(
                MusicCoordinator.FindPlayableIndex([0, 2], 1) == -1 &&
                MusicCoordinator.FindPlayableIndex([0, 2], 2) == 1 &&
                MusicCoordinator.MapPlayableIndex([0, 2], 1) == 2,
                "Music queue did not preserve catalog indexes while excluding invalid scores.");

            await VerifyZeroTimestampChordAsync(context, profile, cancellationToken);
            await VerifyPlaybackControlsAsync(context, score, profile, cancellationToken);
            await VerifyFocusFreezeAndStopAsync(context, score, profile, cancellationToken);
            await VerifyReleaseDoesNotWaitForSendAsync(context, cancellationToken);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static async Task VerifyZeroTimestampChordAsync(
        VerificationContext context,
        InstrumentProfile profile,
        CancellationToken cancellationToken)
    {
        var score = new PerformanceScore
        {
            FullPath = "/tmp/zero-timestamp.json",
            Name = "zero-timestamp",
            Instrument = profile.Name,
            OutputProfileName = profile.Name,
            Format = MusicScoreFormat.Keyboard,
            SourceTimeline = new PerformanceTimeline(
            [
                new PerformanceEvent(TimeSpan.Zero, 'Q', PerformanceEventType.KeyDown),
                new PerformanceEvent(TimeSpan.Zero, 'W', PerformanceEventType.KeyDown),
                new PerformanceEvent(
                    TimeSpan.FromMilliseconds(30), 'Q', PerformanceEventType.KeyUp),
                new PerformanceEvent(
                    TimeSpan.FromMilliseconds(30), 'W', PerformanceEventType.KeyUp),
            ],
            TimeSpan.FromMilliseconds(30)),
        };
        var profileService = new FixedProfileService(profile);
        var transport = new RecordingTransport();
        var gate = new ManualPlaybackGate();
        MusicPlaybackEndedEventArgs? ended = null;
        var service = new MusicPlaybackService(
            new MusicTimelineBuilder(profileService),
            profileService,
            [transport],
            playbackGate: gate);
        service.PlaybackEnded += (_, args) => ended = args;

        var playback = service.RunPlaylistAsync(
            [score],
            0,
            new MusicPlaybackOptions
            {
                InputMode = MusicInputMode.ForegroundSendInput,
                PlaybackMode = MusicPlaybackMode.Sequential,
            },
            cancellationToken);
        await Task.Delay(30, cancellationToken);
        context.Require(
            transport.Events.Count == 0 && service.Snapshot.Position == TimeSpan.Zero,
            "Music playback advanced past the first chord before input focus became available.");
        gate.Open();
        await playback;

        context.Require(
            transport.Events.SequenceEqual(
            [
                "down:Q", "down:W", "up:Q", "up:W",
            ]),
            "Music playback skipped or split the first chord at t=0: " +
            string.Join(" | ", transport.Events));
        context.Require(
            transport.BatchSizes.SequenceEqual([2, 2]),
            "Music playback did not batch events sharing the same timestamp.");
        context.Require(
            ended?.Reason == MusicPlaybackCompletionReason.NaturalCompletion &&
            ended.QueueIndex == 0 &&
            ended.Position == TimeSpan.FromMilliseconds(30),
            "Natural music completion did not report the final track and position.");

        var persistentState = new MusicLibraryState
        {
            CurrentTrackFullPath = "/tmp/previous.json",
            CurrentPositionMilliseconds = 12_345,
        };
        context.Require(
            MusicCoordinator.ApplyPlaybackCompletion(
                persistentState, [score], [0], ended!) &&
            persistentState.CurrentTrackFullPath == score.FullPath &&
            persistentState.CurrentPositionMilliseconds == 0,
            "Natural music completion did not reset the persisted resume point.");
        var cancelled = new MusicPlaybackEndedEventArgs(
            MusicPlaybackCompletionReason.Cancelled,
            0,
            TimeSpan.FromMilliseconds(10));
        persistentState.CurrentPositionMilliseconds = 456;
        context.Require(
            !MusicCoordinator.ApplyPlaybackCompletion(
                persistentState, [score], [0], cancelled) &&
            persistentState.CurrentPositionMilliseconds == 456,
            "Host cancellation incorrectly cleared the persisted music resume point.");
        context.Require(
            MusicCoordinator.NormalizeStartPosition(30_000, TimeSpan.FromSeconds(30)) == 0 &&
            MusicCoordinator.NormalizeStartPosition(29_975, TimeSpan.FromSeconds(30)) == 0 &&
            MusicCoordinator.NormalizeStartPosition(29_000, TimeSpan.FromSeconds(30)) == 29_000,
            "Music resume positions at the natural end were not normalized to replay from zero.");
    }

    private static async Task VerifyPlaybackControlsAsync(
        VerificationContext context,
        PerformanceScore score,
        InstrumentProfile profile,
        CancellationToken cancellationToken)
    {
        var profileService = new FixedProfileService(profile);
        var service = new MusicPlaybackService(
            new MusicTimelineBuilder(profileService),
            profileService,
            [new RecordingTransport()]);
        var playback = service.RunPlaylistAsync(
            [score, score],
            0,
            new MusicPlaybackOptions
            {
                InputMode = MusicInputMode.ForegroundSendInput,
                PlaybackMode = MusicPlaybackMode.Sequential,
            },
            cancellationToken);

        await Task.Delay(40, cancellationToken);
        service.Pause();
        var pausedPosition = service.Snapshot.Position;
        await Task.Delay(60, cancellationToken);
        context.Require(
            service.Snapshot.State == MusicPlaybackState.Paused &&
            Math.Abs((service.Snapshot.Position - pausedPosition).TotalMilliseconds) < 15,
            "Music playback clock advanced while paused.");

        service.Seek(TimeSpan.FromMilliseconds(500));
        context.Require(
            service.Snapshot.State == MusicPlaybackState.Paused &&
            Math.Abs(service.Snapshot.Position.TotalMilliseconds - 500) < 15,
            "Music seek did not update the paused position.");
        service.Resume();
        await Task.Delay(30, cancellationToken);
        context.Require(
            service.Snapshot.State == MusicPlaybackState.Playing &&
            service.Snapshot.Position > TimeSpan.FromMilliseconds(500),
            "Music playback did not resume from the seek position.");

        service.Next();
        await WaitForAsync(
            () => service.Snapshot.QueueIndex == 1,
            TimeSpan.FromSeconds(1),
            cancellationToken);
        service.Previous();
        await WaitForAsync(
            () => service.Snapshot.QueueIndex == 0,
            TimeSpan.FromSeconds(1),
            cancellationToken);
        service.Stop();
        await playback.WaitAsync(TimeSpan.FromSeconds(1), cancellationToken);
        context.Require(
            service.Snapshot.State == MusicPlaybackState.Stopped,
            "Music playback did not stop after exercising playback controls.");
    }

    private static async Task VerifyFocusFreezeAndStopAsync(
        VerificationContext context,
        PerformanceScore score,
        InstrumentProfile profile,
        CancellationToken cancellationToken)
    {
        var profileService = new FixedProfileService(profile);
        var gate = new ManualPlaybackGate();
        MusicPlaybackEndedEventArgs? ended = null;
        var service = new MusicPlaybackService(
            new MusicTimelineBuilder(profileService),
            profileService,
            [new RecordingTransport()],
            playbackGate: gate);
        service.PlaybackEnded += (_, args) => ended = args;
        var playback = service.RunPlaylistAsync(
            [score],
            0,
            new MusicPlaybackOptions
            {
                InputMode = MusicInputMode.ForegroundSendInput,
                PlaybackMode = MusicPlaybackMode.Sequential,
            },
            cancellationToken);

        await Task.Delay(200, cancellationToken);
        context.Require(
            service.Snapshot.Position < TimeSpan.FromMilliseconds(50),
            "Music playback position advanced while input focus was unavailable.");
        service.Pause();
        await WaitForAsync(
            () => service.Snapshot.State == MusicPlaybackState.Paused,
            TimeSpan.FromMilliseconds(300),
            cancellationToken);
        service.Seek(TimeSpan.FromMilliseconds(300));
        service.Resume();
        await Task.Delay(80, cancellationToken);
        context.Require(
            service.Snapshot.Position < TimeSpan.FromMilliseconds(340),
            "Pause, seek, or resume failed to interrupt the blocked focus wait.");
        gate.Open();
        await Task.Delay(60, cancellationToken);
        context.Require(
            service.Snapshot.Position > TimeSpan.FromMilliseconds(300) &&
            service.Snapshot.Position < TimeSpan.FromMilliseconds(440),
            "Music playback caught up elapsed wall time after focus returned.");

        gate.Close();
        await Task.Delay(30, cancellationToken);
        var started = Stopwatch.GetTimestamp();
        service.Stop();
        await playback.WaitAsync(TimeSpan.FromSeconds(1), cancellationToken);
        context.Require(
            Stopwatch.GetElapsedTime(started) < TimeSpan.FromMilliseconds(300),
            "Stopping music did not promptly cancel the focus wait.");
        context.Require(
            ended?.Reason == MusicPlaybackCompletionReason.ExplicitStop,
            "Explicit music stop was not distinguished from host cancellation.");
    }

    private static async Task VerifyReleaseDoesNotWaitForSendAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var transport = new BlockingTransport();
        var keyDown = Task.Run(() => transport.KeyDown('Q'), cancellationToken);
        await transport.SendStarted.Task.WaitAsync(TimeSpan.FromSeconds(1), cancellationToken);
        var release = Task.Run(transport.ReleaseAll, cancellationToken);
        await release.WaitAsync(TimeSpan.FromMilliseconds(300), cancellationToken);
        transport.AllowSend.TrySetResult();
        await keyDown.WaitAsync(TimeSpan.FromSeconds(1), cancellationToken);
        context.Require(
            transport.KeyUpCount >= 1,
            "ReleaseAll waited for an in-flight key send or failed to compensate it.");

        var batchTransport = new BlockingTransport();
        PerformanceEvent[] batchEvents =
        [
            new PerformanceEvent(TimeSpan.Zero, 'Q', PerformanceEventType.KeyDown),
            new PerformanceEvent(TimeSpan.Zero, 'W', PerformanceEventType.KeyDown),
        ];
        var batch = Task.Run(
            () => batchTransport.DispatchBatch(batchEvents, 0, batchEvents.Length),
            cancellationToken);
        await batchTransport.SendStarted.Task.WaitAsync(
            TimeSpan.FromSeconds(1), cancellationToken);
        batchTransport.ReleaseAll();
        batchTransport.AllowSend.TrySetResult();
        await batch.WaitAsync(TimeSpan.FromSeconds(1), cancellationToken);
        context.Require(
            batchTransport.KeyDownCount == 1,
            "ReleaseAll did not invalidate the remaining events in an in-flight chord batch.");
    }

    private static async Task WaitForAsync(
        Func<bool> condition,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var started = Stopwatch.GetTimestamp();
        while (!condition())
        {
            if (Stopwatch.GetElapsedTime(started) >= timeout)
            {
                throw new TimeoutException("Timed out waiting for music playback state.");
            }
            await Task.Delay(10, cancellationToken);
        }
    }

    private sealed class RecordingTransport : KeyInputTransportBase
    {
        public List<string> Events { get; } = [];
        public List<int> BatchSizes { get; } = [];

        public override MusicInputMode Mode => MusicInputMode.ForegroundSendInput;

        protected override void SendKeyDown(char key) => Events.Add($"down:{key}");

        protected override void SendKeyUp(char key) => Events.Add($"up:{key}");

        public override void DispatchBatch(
            IReadOnlyList<PerformanceEvent> events,
            int startIndex,
            int count)
        {
            BatchSizes.Add(count);
            base.DispatchBatch(events, startIndex, count);
        }
    }

    private sealed class BlockingTransport : KeyInputTransportBase
    {
        private int _keyDownCount;
        private int _keyUpCount;
        public TaskCompletionSource SendStarted { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource AllowSend { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);
        public int KeyUpCount => Volatile.Read(ref _keyUpCount);
        public int KeyDownCount => Volatile.Read(ref _keyDownCount);
        public override MusicInputMode Mode => MusicInputMode.ForegroundSendInput;

        protected override void SendKeyDown(char key)
        {
            Interlocked.Increment(ref _keyDownCount);
            SendStarted.TrySetResult();
            AllowSend.Task.GetAwaiter().GetResult();
        }

        protected override void SendKeyUp(char key) => Interlocked.Increment(ref _keyUpCount);
    }

    private sealed class ManualPlaybackGate : IMusicPlaybackGate
    {
        private volatile bool _isOpen;
        private TaskCompletionSource _available = CreateSource();

        public bool IsAvailable(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return _isOpen;
        }

        public Task WaitUntilAvailableAsync(CancellationToken cancellationToken) =>
            _available.Task.WaitAsync(cancellationToken);

        public void Open()
        {
            _isOpen = true;
            _available.TrySetResult();
        }

        public void Close()
        {
            _isOpen = false;
            _available = CreateSource();
        }

        private static TaskCompletionSource CreateSource() =>
            new(TaskCreationOptions.RunContinuationsAsynchronously);
    }

    private sealed class FixedProfileService(InstrumentProfile profile)
        : IInstrumentProfileService
    {
        public ObservableCollection<InstrumentProfile> Profiles { get; } = [profile];

        public InstrumentProfile StandardProfile => profile;

        public InstrumentProfile Find(string? name) => profile;

        public void Save()
        {
        }
    }
}
