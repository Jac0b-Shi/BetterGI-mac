using System.Text.Json;
using System.Text.Json.Nodes;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoFight.Model;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.SkillCd;
using BetterGenshinImpact.Platform.Abstractions;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacSkillCdRuntimePlatform : ISkillCdRuntimePlatform
{
    private readonly Func<ISystemInfo> _systemInfo;
    private readonly PlatformCallbackChannel _callbacks;
    private readonly string _sessionToken;
    private readonly CancellationToken _cancellationToken;

    public MacSkillCdRuntimePlatform(RuntimeLayout layout, Func<ISystemInfo> systemInfo, ILoggerFactory loggerFactory,
        PlatformCallbackChannel callbacks, string sessionToken, CancellationToken cancellationToken)
    {
        _systemInfo = systemInfo;
        _callbacks = callbacks;
        _sessionToken = sessionToken;
        _cancellationToken = cancellationToken;
        Logger = loggerFactory.CreateLogger<SkillCdTrigger>();
        var root = LoadRoot(layout);
        Config = root["skillCdConfig"]?.Deserialize<SkillCdConfig>(ConfigJson.Options) ?? new SkillCdConfig();
        TriggerInterval = root["triggerInterval"]?.GetValue<int>() ?? 50;
    }

    public SkillCdConfig Config { get; }
    public int TriggerInterval { get; }
    public ISystemInfo SystemInfo => _systemInfo();
    public ILogger Logger { get; }
    public bool IsElementalSkillDown() => Query("isGameActionDown", "gameAction", "elementalSkill");
    public bool IsPartySlotDown(int zeroBasedSlot) => Query("isKeyDown", "key", (zeroBasedSlot + 1).ToString());
    public CombatScenes? TrySyncCombatScenesSilent() => RunnerContext.Instance.TrySyncCombatScenesSilent();

    public void Publish(IReadOnlyList<SkillCdTextCommand>? commands)
    {
        var response = Invoke("overlay.command", JObject.FromObject(new
        {
            name = "SkillCdText", operation = commands is null ? "removeText" : "setText", commands
        }));
        if (response.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException("SkillCd overlay command was not acknowledged.");
    }

    private bool Query(string action, string key, string value) =>
        Invoke("input.query", new JObject { ["action"] = action, [key] = value }).Value<bool?>("isDown")
        ?? throw new InvalidDataException("input.query did not return isDown.");
    private JToken Invoke(string method, JObject parameters) =>
        _callbacks.InvokeAsync(method, parameters, _sessionToken, _cancellationToken).GetAwaiter().GetResult()
        ?? throw new InvalidDataException($"{method} returned an empty response.");
    private static JsonObject LoadRoot(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return new JsonObject();
        return JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip }) as JsonObject
            ?? throw new InvalidDataException("User/config.json root must be an object.");
    }
}
