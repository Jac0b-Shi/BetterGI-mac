using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Verification.Framework;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class SoloTaskSettingsSuite : IVerificationSuite
{
    public string Name => "solo-settings";

    public async Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        var root = Path.Combine(Path.GetTempPath(), $"bettergi-solo-fast-{Guid.NewGuid():N}");
        try
        {
            var layout = new RuntimeLayout(root);
            layout.EnsureCreated();
            await File.WriteAllTextAsync(Path.Combine(layout.UserPath, "config.json"), """
                {
                  "autoLeyLineOutcropConfig": {
                    "leyLineOutcropType": "启示之花",
                    "country": "蒙德",
                    "isGoToSynthesizer": true,
                    "fightConfig": {
                      "strategyName": "",
                      "fightFinishDetectEnabled": false,
                      "finishDetectConfig": { "fastCheckEnabled": true },
                      "timeout": 120
                    }
                  }
                }
                """, cancellationToken);

            var catalog = new SoloTaskSettingsCatalog(layout);
            var initial = JObject.FromObject(catalog.Get("AutoLeyLineOutcrop"));
            context.Require(initial.Value<string>("leyLineOutcropType") == "启示之花" &&
                            initial["countryOptions"]?.Values<string>().Contains("挪德卡莱") == true,
                "AutoLeyLineOutcrop settings did not expose the upstream options.");

            _ = catalog.Save("AutoLeyLineOutcrop", JObject.FromObject(new
            {
                leyLineOutcropType = "藏金之花",
                country = "枫丹",
                strategyName = "",
                actionSchedulerByCd = "钟离,12",
                seekEnemyEnabled = true,
                seekEnemyRotaryFactor = 8,
                seekEnemyIntervalSeconds = 4,
                kazuhaPickupEnabled = true,
                qinDoublePickUp = true,
                scanDropsAfterRewardEnabled = true,
                scanDropsAfterRewardSeconds = 15,
                isResinExhaustionMode = true,
                openModeCountMin = true,
                count = 9,
                useTransientResin = true,
                useFragileResin = false,
                team = "战斗队",
                friendshipTeam = "好感队",
                timeout = 180,
                useAdventurerHandbook = true,
                isNotification = true,
            }));

            var persisted = JObject.Parse(await File.ReadAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"), cancellationToken));
            var node = persisted["autoLeyLineOutcropConfig"]!;
            var config = catalog.BuildAutoLeyLineOutcropConfig();
            context.Require(node.Value<bool>("isGoToSynthesizer") &&
                            node["fightConfig"]?.Value<bool>("fightFinishDetectEnabled") == false &&
                            node["fightConfig"]?["finishDetectConfig"]?
                                .Value<bool>("fastCheckEnabled") == true,
                "AutoLeyLineOutcrop save did not preserve hidden upstream settings.");
            context.Require(config.LeyLineOutcropType == "藏金之花" &&
                            config.Country == "枫丹" && config.Count == 9 &&
                            config.FightConfig.ActionSchedulerByCd == "钟离,12" &&
                            config.FightConfig.Timeout == 180 && config.Timeout == 180 &&
                            config.UseAdventurerHandbook && config.IsNotification,
                "AutoLeyLineOutcrop task config did not reflect the saved Core-owned settings.");

            var platform = new RecordingDispatcherPlatform();
            var coordinator = new SoloTaskCoordinator(platform, catalog, CancellationToken.None);
            var descriptors = JArray.FromObject(coordinator.List());
            var descriptor = descriptors.Single(item =>
                item.Value<string>("name") == "AutoLeyLineOutcrop");
            context.Require(descriptor.Value<bool>("available") &&
                            descriptor.Value<bool>("settingsAvailable"),
                "AutoLeyLineOutcrop was not exposed as a composed configurable solo task.");
            _ = coordinator.Start("AutoLeyLineOutcrop");
            for (var retry = 0; retry < 20 && platform.Request is null; retry++)
                await Task.Delay(10, cancellationToken);
            context.Require(platform.Request is DispatcherLeyLineTaskRequest request &&
                            request.Config.Country == "枫丹" && request.Config.Count == 9,
                "SoloTaskCoordinator did not dispatch the Core-owned AutoLeyLineOutcrop config.");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private sealed class RecordingDispatcherPlatform : IDispatcherRuntimePlatform
    {
        public DispatcherSoloTaskRequest? Request { get; private set; }
        public CancellationToken GlobalCancellationToken => CancellationToken.None;
        public int AutoWoodRoundNum => 0;
        public int AutoWoodDailyMaxCount => 0;
        public string AutoBossStrategyName => string.Empty;
        public DispatcherAutoEatSettings AutoEatSettings => new(0, 0, false);
        public void ClearTriggers() { }
        public bool AddTrigger(string name, object? config) => true;
        public bool GetTcgStrategy(out string content) { content = string.Empty; return false; }
        public bool GetFightStrategy(string? strategyName, out string path)
        {
            path = string.Empty;
            return false;
        }
        public Task<object?> ExecuteSoloTask(
            DispatcherSoloTaskRequest request, CancellationToken cancellationToken)
        {
            Request = request;
            return Task.FromResult<object?>(null);
        }
        public Task<object?> RunParameterizedTask(
            string name, object parameter, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }
}
