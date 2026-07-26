using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.AutoPathing.Model;
using BetterGenshinImpact.GameTask.AutoPathing.Model.Enum;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.GameTask.FarmingPlan;
using BetterGenshinImpact.Service;
using BetterGenshinImpact.Verification.Framework;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using OpenCvSharp;
using System.Text.Json;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class PathRecorderSuite : IVerificationSuite
{
    public string Name => "path-recorder";

    public Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var root = Path.Combine(
            Path.GetTempPath(),
            $"bettergi-path-recorder-{Guid.NewGuid():N}");
        try
        {
            ScriptServicePlatform.Configure(
                new RecordingScriptServicePlatform(root));
            var platform = new RecordingPlatform(root);
            var positions = new Queue<Point2f>(
            [
                new Point2f(12.5f, -8.25f),
                new Point2f(18.75f, -3.5f),
            ]);
            var provider = new RecordingPositionProvider(positions);
            var recorder = new PathRecorderTask(
                platform,
                provider,
                new FixedTimeProvider(
                    new DateTimeOffset(
                        2026, 7, 24, 15, 16, 17, TimeSpan.Zero)));

            var inactive = recorder.AddWaypoint();
            var started = recorder.Toggle();
            var added = recorder.AddWaypoint();
            var saved = recorder.Toggle();

            context.Require(
                inactive.State == "inactive" &&
                started.State == "recording" &&
                started.WaypointCount == 1 &&
                added.State == "waypointAdded" &&
                added.WaypointCount == 2 &&
                saved.State == "saved" &&
                saved.WaypointCount == 2 &&
                saved.Path == Path.Combine(
                    root,
                    "20260724_151617.json") &&
                File.Exists(saved.Path) &&
                provider.WarmUpMethods.SequenceEqual(["TemplateMatch"]) &&
                provider.Requests.SequenceEqual(
                [
                    ("TheChasm", "TemplateMatch"),
                    ("TheChasm", "TemplateMatch"),
                ]),
                "Path recorder did not preserve the upstream start/add/save lifecycle.");

            var document = JsonSerializer.Deserialize<PathingTask>(
                File.ReadAllText(saved.Path!),
                PathingJson.Options)
                ?? throw new InvalidDataException(
                    "Saved path recorder output was empty.");
            context.Require(
                document.Info.Name == "未命名路线" &&
                document.Info.Type == PathingTaskType.Collect.Code &&
                document.Info.MapName == "TheChasm" &&
                document.Info.MapMatchMethod == "TemplateMatch" &&
                document.Info.BgiVersion == "0.62.1-verification" &&
                document.Positions.Count == 2 &&
                document.Positions[0].Type == WaypointType.Teleport.Code &&
                document.Positions[0].MoveMode == MoveModeEnum.Walk.Code &&
                document.Positions[0].X == 12.5 &&
                document.Positions[0].Y == -8.25 &&
                document.Positions[1].Type == WaypointType.Path.Code &&
                document.Positions[1].X == 18.75 &&
                document.Positions[1].Y == -3.5,
                "Path recorder output did not preserve upstream route metadata and waypoint semantics.");

            platform.IsEditorOpenValue = true;
            var editorRecorder = new PathRecorderTask(
                platform,
                new RecordingPositionProvider(
                    new Queue<Point2f>([new Point2f(1, 2)])));
            var editorStarted = editorRecorder.Toggle();
            var editorStopped = editorRecorder.Toggle();
            context.Require(
                editorStarted.State == "recording" &&
                editorStopped.State == "editor" &&
                editorStopped.Path is null &&
                platform.Published.Count == 1,
                "Path recorder did not retain the upstream optional editor branch.");
        }
        finally
        {
            if (Directory.Exists(root))
                Directory.Delete(root, recursive: true);
        }
        return Task.CompletedTask;
    }

    private sealed class RecordingPlatform(string outputDirectory)
        : IPathRecorderRuntimePlatform
    {
        public bool IsEditorOpenValue { get; set; }
        public List<Waypoint> Published { get; } = [];

        public PathRecorderSettings Settings => new(
            "TheChasm",
            "TemplateMatch",
            outputDirectory,
            "0.62.1-verification");

        public bool IsEditorOpen => IsEditorOpenValue;
        public ILogger Logger { get; } =
            NullLogger<RecordingPlatform>.Instance;

        public void PublishWaypoint(Waypoint waypoint)
        {
            if (IsEditorOpen)
                Published.Add(waypoint);
        }
    }

    private sealed class RecordingPositionProvider(
        Queue<Point2f> positions) : IPathRecorderPositionProvider
    {
        public List<string> WarmUpMethods { get; } = [];
        public List<(string MapName, string Method)> Requests { get; } = [];

        public void WarmUp(string matchingMethod) =>
            WarmUpMethods.Add(matchingMethod);

        public Point2f? GetCurrentPosition(
            string mapName,
            string matchingMethod)
        {
            Requests.Add((mapName, matchingMethod));
            return positions.Count == 0 ? null : positions.Dequeue();
        }
    }

    private sealed class FixedTimeProvider(DateTimeOffset utcNow)
        : TimeProvider
    {
        public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;
        public override DateTimeOffset GetUtcNow() => utcNow;
    }

    private sealed class RecordingScriptServicePlatform(string root)
        : IScriptServicePlatform
    {
        public ILogger Logger { get; } =
            NullLogger<RecordingScriptServicePlatform>.Instance;
        public string AutoPathingRoot => root;
        public string MapMatchingMethod => "TemplateMatch";
        public IReadOnlyList<ScriptGroup> ScriptGroups => [];
        public bool FarmingPlanEnabled => false;
        public bool IsDailyFarmingLimitReached(
            FarmingSession farmingSession,
            out string message)
        {
            message = "";
            return false;
        }
        public void ClearTriggers()
        {
        }
        public SchedulerRestartPolicy RestartPolicy => default;
        public void SetCurrentScriptProject(ScriptGroupProject project)
        {
        }
        public Task StartGameTask(bool waitForMainUi) => Task.CompletedTask;
        public Task HandleBlessingOfTheWelkinMoon(
            CancellationToken cancellationToken) => Task.CompletedTask;
        public void NotifyGroupStart(string groupName)
        {
        }
        public void NotifyGroupEndSuccess(string groupName)
        {
        }
        public void NotifyGroupEndError(string message)
        {
        }
        public void CloseGame()
        {
        }
        public void RestartApplication(string taskProgressName)
        {
        }
    }
}
