using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.Core.Host;
using BetterGenshinImpact.Service;
using BetterGenshinImpact.GameTask.FarmingPlan;
using Microsoft.Extensions.Logging;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using BetterGenshinImpact.Core.Config;
using Newtonsoft.Json.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Runtime.Versioning;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>macOS composition for scheduler storage/configuration and terminal side effects.</summary>
[SupportedOSPlatform("macos")]
public sealed class MacScriptServicePlatform(
    RuntimeLayout layout,
    ILogger logger,
    MacScriptHostServices scriptHostServices,
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken hostCancellationToken,
    SharedCaptureRingReader captureRing,
    MacGameTaskManagerPlatform gameTaskManagerPlatform) : IScriptServicePlatform
{
    private string _mapMatchingMethod = "TemplateMatch";
    private readonly JsonObject? _configRoot = LoadConfigRoot(layout);

    public ILogger Logger { get; } = logger;
    public string AutoPathingRoot => Path.Combine(layout.UserPath, "AutoPathing");
    public string MapMatchingMethod => Volatile.Read(ref _mapMatchingMethod);
    public IReadOnlyList<ScriptGroup> ScriptGroups => Directory
        .EnumerateFiles(layout.ScriptGroupPath, "*.json", SearchOption.TopDirectoryOnly)
        .OrderBy(path => path, StringComparer.Ordinal)
        .Select(path => ScriptGroup.FromJson(File.ReadAllText(path)))
        .ToArray();
    public bool FarmingPlanEnabled => LoadOtherConfig().FarmingPlanConfig.Enabled;
    public bool IsDailyFarmingLimitReached(FarmingSession farmingSession, out string message) =>
        FarmingStatsRecorder.IsDailyFarmingLimitReached(farmingSession, out message);
    public void ClearTriggers() => GameTaskManager.ClearTriggers();
    public SchedulerRestartPolicy RestartPolicy
    {
        get
        {
            var restart = LoadOtherConfig().AutoRestartConfig;
            var start = LoadGenshinStartConfig();
            return new SchedulerRestartPolicy(
                restart.Enabled, restart.FailureCount, restart.RestartGameTogether,
                start.LinkedStartEnabled, start.AutoEnterGameEnabled);
        }
    }
    public void SetCurrentScriptProject(ScriptGroupProject project) => scriptHostServices.SetCurrentProject(project);

    public void SetMapMatchingMethod(string value)
    {
        if (value is not ("TemplateMatch" or "SIFT"))
            throw new ArgumentOutOfRangeException(nameof(value), "Unsupported map matching method.");
        Volatile.Write(ref _mapMatchingMethod, value);
    }

    public async Task StartGameTask(bool waitForMainUi)
    {
        RequireAcknowledgement("window.activate", null);
        if (!waitForMainUi)
            return;

        using var assets = new MacMainUiRecognitionAssets(layout, gameTaskManagerPlatform.SystemInfo);
        var first = true;
        while (true)
        {
            hostCancellationToken.ThrowIfCancellationRequested();
            if (CancellationContext.Instance.IsCancellationRequested)
            {
                Logger.LogInformation("检测到停止指令，退出启动等待");
                return;
            }

            var response = await callbacks.InvokeAsync(
                "capture.request", null, sessionToken, hostCancellationToken)
                ?? throw new InvalidDataException("capture.request returned an empty response.");
            using var content = captureRing.Read(response);
            if (Bv.IsInMainUi(content, assets.PaimonMenu, assets.ReviveConfirm, "复苏"))
                return;
            if (first)
            {
                first = false;
                Logger.LogInformation("当前不在游戏主界面，等待进入主界面后执行任务...");
            }
            await Task.Delay(500, hostCancellationToken);
        }
    }
    public async Task HandleBlessingOfTheWelkinMoon(CancellationToken cancellationToken)
    {
        var now = ScriptHostServices.ServerTimeNow.AddMinutes(5);
        if (now.Hour != 4 || now.Minute >= 10)
            return;

        using var assets = new MacMainUiRecognitionAssets(layout, gameTaskManagerPlatform.SystemInfo);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, hostCancellationToken);
        using var firstFrame = await Capture(linked.Token);
        if (!IsBlessing(firstFrame, assets))
            return;

        Logger.LogInformation("检测到空月祝福界面，自动点击");
        MoveTo1080P(100, 100);
        for (int i = 0, consecutiveAbsent = 0; i < 20 && consecutiveAbsent < 3; ++i)
        {
            if (consecutiveAbsent == 0)
            {
                Click();
                await Task.Delay(100, linked.Token);
                Click();
            }
            await Task.Delay(500, linked.Token);
            using var frame = await Capture(linked.Token);
            consecutiveAbsent = IsBlessing(frame, assets) ? 0 : consecutiveAbsent + 1;
        }
        Logger.LogInformation("空月祝福处理完毕");
    }
    public void NotifyGroupStart(string groupName) => Notify("info", $"配置组{groupName}启动");
    public void NotifyGroupEndSuccess(string groupName) => Notify("info", $"配置组{groupName}结束");
    public void NotifyGroupEndError(string message) => Notify("error", message);
    public void CloseGame() => RequireAcknowledgement("game.close", null);
    public void RestartApplication(string taskProgressName)
    {
        if (string.IsNullOrWhiteSpace(taskProgressName))
            throw new ArgumentException("Task progress name cannot be empty.", nameof(taskProgressName));
        RequireAcknowledgement("application.restart", JObject.FromObject(new { taskProgressName }));
    }

    private OtherConfig LoadOtherConfig() =>
        _configRoot?["otherConfig"]?.Deserialize<OtherConfig>(ConfigJson.Options)
        ?? new OtherConfig();

    private GenshinStartConfig LoadGenshinStartConfig() =>
        _configRoot?["genshinStartConfig"]?.Deserialize<GenshinStartConfig>(ConfigJson.Options)
        ?? new GenshinStartConfig();

    private static JsonObject? LoadConfigRoot(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return null;
        return JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
    }

    private void RequireAcknowledgement(string method, JObject? parameters)
    {
        var response = callbacks.InvokeAsync(method, parameters, sessionToken, hostCancellationToken)
            .GetAwaiter().GetResult();
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException($"{method} did not return acknowledged=true.");
    }

    private async Task<BetterGenshinImpact.GameTask.Model.Area.ImageRegion> Capture(CancellationToken cancellationToken)
    {
        var response = await callbacks.InvokeAsync("capture.request", null, sessionToken, cancellationToken)
            ?? throw new InvalidDataException("capture.request returned an empty response.");
        return captureRing.Read(response);
    }

    private static bool IsBlessing(
        BetterGenshinImpact.GameTask.Model.Area.ImageRegion frame,
        MacMainUiRecognitionAssets assets)
    {
        if (Bv.IsInBlessingOfTheWelkinMoon(frame, assets.GirlMoon, assets.WelkinMoon))
            return true;
        using var primogem = frame.Find(assets.Primogem);
        return primogem.IsExist();
    }

    private void MoveTo1080P(int x, int y)
    {
        var size = gameTaskManagerPlatform.SystemInfo.GameScreenSize;
        RequireAcknowledgement("input.dispatch", JObject.FromObject(new
        {
            action = "moveMouseToGame",
            x = (int)Math.Round(x * size.Width / 1920d),
            y = (int)Math.Round(y * size.Height / 1080d),
            gameWidth = size.Width,
            gameHeight = size.Height
        }));
    }

    private void Click() => RequireAcknowledgement("input.dispatch",
        JObject.FromObject(new { action = "mouseClick", button = "left" }));

    private void Notify(string kind, string message) => RequireAcknowledgement(
        "notification.emit", JObject.FromObject(new { kind, message }));
}
