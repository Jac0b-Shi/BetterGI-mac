using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Protocol;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Script.Group;
using BetterGenshinImpact.Verification.Framework;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class PathingCatalogSuite : IVerificationSuite
{
    public string Name => "pathing-catalog";

    public async Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var root = Path.Combine(
            Path.GetTempPath(), $"bettergi-pathing-catalog-{Guid.NewGuid():N}");
        var previousRoot = Global.StartUpPath;
        try
        {
            Global.StartUpPath = root;
            var layout = new RuntimeLayout(root);
            layout.EnsureCreated();
            var autoFightAssets = Path.Combine(
                root, "GameTask", "AutoFight", "Assets");
            Directory.CreateDirectory(autoFightAssets);
            await File.WriteAllTextAsync(
                Path.Combine(autoFightAssets, "combat_avatar.json"),
                """[{"alias":["测试角色"],"id":"1","name":"测试角色","nameEn":"Fixture","weapon":"1"}]""",
                cancellationToken);
            var routes = Path.Combine(layout.UserPath, "AutoPathing", "采集", "甜甜花");
            Directory.CreateDirectory(routes);
            await File.WriteAllTextAsync(
                Path.Combine(routes, "route.json"),
                """{"info":{"name":"Fixture"},"positions":[]}""",
                cancellationToken);
            await File.WriteAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"),
                """{"unrelated":{"preserve":true}}""",
                cancellationToken);

            var catalog = new PathingCatalog(layout);
            var entries = catalog.List();
            context.Require(
                entries.Any(entry =>
                    entry is { Id: "采集", ParentId: null, IsDirectory: true }) &&
                entries.Any(entry =>
                    entry is
                    {
                        Id: "采集/甜甜花/route.json",
                        ParentId: "采集/甜甜花",
                        IsDirectory: false
                    }),
                "Pathing catalog did not preserve the upstream directory tree.");

            var project = catalog.BuildProject("采集/甜甜花/route.json");
            context.Require(
                project.Type == "Pathing" &&
                project.FolderName == Path.Combine("采集", "甜甜花") &&
                project.Name == "route.json",
                "Pathing catalog did not build the real upstream project identity.");

            var groupPath = Path.Combine(layout.ScriptGroupPath, "路线组.json");
            await File.WriteAllTextAsync(
                groupPath,
                """
                {
                  "index": 1,
                  "name": "路线组",
                  "config": {
                    "pathingConfig": {
                      "enabled": true,
                      "autoPickEnabled": false,
                      "partyName": "采集队"
                    }
                  },
                  "projects": []
                }
                """,
                cancellationToken);
            var groupCatalog = new ScriptGroupCatalog(layout);
            var candidate = groupCatalog.ListAddCandidates("Pathing").Single(item =>
                item.Id == Path.Combine("采集", "甜甜花", "route.json"));
            _ = groupCatalog.AddProjects(
                "路线组",
                "Pathing",
                new JArray(candidate.Id),
                shellCommand: null);
            var scheduledGroup = ScriptGroup.FromJson(
                await File.ReadAllTextAsync(groupPath, cancellationToken));
            var scheduledProject = scheduledGroup.Projects.Single();
            context.Require(
                scheduledProject.Type == "Pathing" &&
                scheduledProject.Name == "route.json" &&
                scheduledProject.FolderName == Path.Combine("采集", "甜甜花") &&
                ReferenceEquals(scheduledProject.GroupInfo, scheduledGroup) &&
                scheduledProject.GroupInfo.Config.PathingConfig.Enabled &&
                !scheduledProject.GroupInfo.Config.PathingConfig.AutoPickEnabled &&
                scheduledProject.GroupInfo.Config.PathingConfig.PartyName == "采集队",
                "Scheduler pathing project lost its route identity or group-level pathing configuration.");

            var updateObserved = false;
            catalog.AttachSettingsUpdated(_ => updateObserved = true);
            _ = catalog.SaveSettings(JObject.FromObject(new
            {
                partyConditions = new[]
                {
                    new
                    {
                        subject = "采集物",
                        predicate = "包含",
                        objects = new[] { "甜甜花" },
                        result = "采集队"
                    }
                },
                avatarConditions = Array.Empty<object>(),
                useGadgetIntervalMs = 1200,
                autoEatEnabled = true,
                recoverTiming = nameof(RecoverTiming.OnlyTeleport),
            }));
            var config = JObject.Parse(
                await File.ReadAllTextAsync(
                    Path.Combine(layout.UserPath, "config.json"),
                    cancellationToken));
            context.Require(
                updateObserved &&
                config["unrelated"]?.Value<bool>("preserve") == true &&
                config["pathingConditionConfig"]?.Value<int>("useGadgetIntervalMs") == 1200 &&
                config["pathingConditionConfig"]?.Value<int>("recoverTiming") ==
                (int)RecoverTiming.OnlyTeleport,
                "Pathing settings did not preserve unrelated config or hot-update the runtime.");

            var traversalRejected = false;
            try
            {
                _ = catalog.BuildProject("../outside.json");
            }
            catch (ArgumentException)
            {
                traversalRejected = true;
            }
            context.Require(
                traversalRejected,
                "Pathing catalog accepted a route outside User/AutoPathing.");
        }
        finally
        {
            Global.StartUpPath = previousRoot;
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }
}
