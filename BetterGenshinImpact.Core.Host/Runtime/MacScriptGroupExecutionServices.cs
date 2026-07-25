using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.FarmingPlan;
using BetterGenshinImpact.Core.Config;
using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Platform.Abstractions;
using BetterGenshinImpact.GameTask;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacScriptGroupExecutionServices : IScriptGroupExecutionServices
{
    private readonly RuntimeLayout _layout;
    private readonly PathingPartyConfig _defaultPartyConfig;
    private readonly IAutoPickRuntimeState _autoPickRuntimeState;
    private readonly IInputBackend _inputBackend;
    private readonly Func<ISystemInfo> _getSystemInfo;
    private readonly IAutoPickConfigProvider _autoPickConfigProvider;
    private readonly IPaddleAutoPickTextRecognizer _paddleRecognizer;
    private readonly IYapAutoPickTextRecognizer _yapRecognizer;

    public MacScriptGroupExecutionServices(
        RuntimeLayout layout,
        IAutoPickRuntimeState autoPickRuntimeState,
        IInputBackend inputBackend,
        Func<ISystemInfo> getSystemInfo,
        IAutoPickConfigProvider autoPickConfigProvider,
        IPaddleAutoPickTextRecognizer paddleRecognizer,
        IYapAutoPickTextRecognizer yapRecognizer)
    {
        _layout = layout;
        _autoPickRuntimeState = autoPickRuntimeState;
        _inputBackend = inputBackend;
        _getSystemInfo = getSystemInfo ?? throw new ArgumentNullException(nameof(getSystemInfo));
        _autoPickConfigProvider = autoPickConfigProvider;
        _paddleRecognizer = paddleRecognizer;
        _yapRecognizer = yapRecognizer;
        var root = LoadRoot(layout);
        var condition = root?["pathingConditionConfig"]?.Deserialize<PathingConditionConfig>(ConfigJson.Options)
            ?? new PathingConditionConfig();
        _defaultPartyConfig = new PathingPartyConfig
        {
            OnlyInTeleportRecover = condition.OnlyInTeleportRecover,
            UseGadgetIntervalMs = condition.UseGadgetIntervalMs,
            AutoEatEnabled = condition.AutoEatEnabled
        };
    }

    public PathingPartyConfig DefaultPartyConfig => CreateDefaultPartyConfig();

    public PathingPartyConfig CreateDefaultPartyConfig() => new()
    {
        OnlyInTeleportRecover = _defaultPartyConfig.OnlyInTeleportRecover,
        UseGadgetIntervalMs = _defaultPartyConfig.UseGadgetIntervalMs,
        AutoEatEnabled = _defaultPartyConfig.AutoEatEnabled,
    };

    public IPathExecutor CreatePathExecutor(CancellationToken cancellationToken) => new PathExecutor(
        cancellationToken, PathExecutorPlatform.Current, PathExecutorAutoSkipPlatform.Current, this);

    public void AddAutoPickTrigger()
    {
        if (!GameTaskManager.AddTrigger(
                "AutoPick", null, _autoPickRuntimeState, _inputBackend, _getSystemInfo(),
                _autoPickConfigProvider, _paddleRecognizer, _yapRecognizer))
            throw new CapabilityUnavailableException("The shared AutoPick trigger could not be created.");
        GameTaskManager.TriggerDictionary!["AutoPick"].Init();
        GameTaskManager.TriggerDictionary["AutoPick"].IsEnabled = true;
    }

    public PathingFailurePolicy PathingFailurePolicy
    {
        get
        {
            var restart = LoadRoot(_layout)?["otherConfig"]?["autoRestartConfig"]
                ?.Deserialize<OtherConfig.AutoRestart>(ConfigJson.Options)
                ?? new OtherConfig.AutoRestart();
            return new PathingFailurePolicy(
                restart.Enabled,
                restart.IsPathingFailureExceptional,
                restart.IsFightFailureExceptional);
        }
    }

    public void RecordFarmingSession(FarmingSession session, FarmingRouteInfo route) =>
        FarmingStatsRecorder.RecordFarmingSession(session, route);

    private static JsonObject? LoadRoot(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return null;
        return JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
    }
}
