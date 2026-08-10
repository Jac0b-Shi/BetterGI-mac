using BetterGenshinImpact.GameTask.Music.Model;
using BetterGenshinImpact.GameTask.Music.Service;
using BetterGenshinImpact.Verification.Framework;
using System.Collections.ObjectModel;

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
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private sealed class RecordingTransport : KeyInputTransportBase
    {
        public List<string> Events { get; } = [];

        public override MusicInputMode Mode => MusicInputMode.ForegroundSendInput;

        protected override void SendKeyDown(char key) => Events.Add($"down:{key}");

        protected override void SendKeyUp(char key) => Events.Add($"up:{key}");
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
