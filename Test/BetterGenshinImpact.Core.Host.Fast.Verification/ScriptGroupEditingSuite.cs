using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Verification.Framework;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class ScriptGroupEditingSuite : IVerificationSuite
{
    public string Name => "script-group-editing";

    public async Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        var root = Path.Combine(Path.GetTempPath(), $"bettergi-script-group-{Guid.NewGuid():N}");
        var previousRoot = Global.StartUpPath;
        try
        {
            Global.StartUpPath = root;
            var layout = new RuntimeLayout(root);
            layout.EnsureCreated();
            var fightStrategyFolder = Path.Combine(layout.UserPath, "AutoFight");
            Directory.CreateDirectory(fightStrategyFolder);
            await File.WriteAllTextAsync(
                Path.Combine(fightStrategyFolder, "Farming.txt"),
                "钟离 e",
                cancellationToken);
            var script = Path.Combine(layout.UserPath, "JsScript", "Fixture");
            Directory.CreateDirectory(script);
            await File.WriteAllTextAsync(Path.Combine(script, "main.js"), "log.info('fixture');", cancellationToken);
            await File.WriteAllTextAsync(Path.Combine(script, "manifest.json"), """
                {
                  "manifest_version": 1,
                  "name": "Fixture Script",
                  "version": "1.0.0",
                  "description": "fixture",
                  "authors": [{"name": "test", "links": ""}],
                  "settings_ui": "settings.json",
                  "http_allowed_urls": ["https://example.com/api"],
                  "main": "main.js"
                }
                """, cancellationToken);
            await File.WriteAllTextAsync(Path.Combine(script, "settings.json"), """
                [
                  {"name":"mode","type":"select","label":"Mode","options":["A","B"],"default":"A"},
                  {"name":"enabled","type":"checkbox","label":"Enabled","default":true},
                  {"name":"targets","type":"multi-checkbox","label":"Targets","options":["One","Two"],"default":["One"]}
                ]
                """, cancellationToken);
            await File.WriteAllTextAsync(Path.Combine(layout.ScriptGroupPath, "Fixture Group.json"), """
                {
                  "index": 1,
                  "name": "Fixture Group",
                  "config": {
                    "pathingConfig": {
                      "enabled": true,
                      "partyName": "Original",
                      "distance": 45,
                      "autoEatConfig": {
                        "defaultAtkBoostingDishName": "仙跳墙"
                      },
                      "autoFightConfig": {
                        "strategyName": "Farming",
                        "onlyPickEliteDropsMode": "DisableAutoPickupForNonElite",
                        "battleThresholdForLoot": 3,
                        "kazuhaPartyName": "拾取队",
                        "finishDetectConfig": {
                          "fastCheckEnabled": true
                        }
                      }
                    },
                    "shellConfig": {"timeout":60},
                    "enableShellConfig":false
                  },
                  "projects": [{
                    "index":1,"name":"Fixture Script","folderName":"Fixture","type":"Javascript","status":"Enabled","schedule":"Daily","runNum":2,
                    "allowJsNotification":true,"allowJsHTTPHash":"","jsScriptSettingsObject":{"legacy":"keep"}
                  }]
                }
                """, cancellationToken);

            var catalog = new ScriptGroupCatalog(layout);
            var custom = catalog.GetProjectCustomSettings("Fixture Group", 1);
            context.Require(custom.Schema is not null && custom.Values.Value<string>("mode") == "A" &&
                            custom.Values.Value<bool>("enabled") && custom.Values["targets"] is JArray,
                "Custom settings did not apply the upstream schema defaults.");

            _ = catalog.SaveProjectCustomSettings("Fixture Group", 1, JObject.FromObject(new
            {
                mode = "B", enabled = false, targets = new[] { "Two" }, injected = "reject"
            }));
            var saved = catalog.Get("Fixture Group").Document;
            var values = saved["projects"]![0]!["jsScriptSettingsObject"]!;
            context.Require(values.Value<string>("mode") == "B" && values.Value<bool>("enabled") == false &&
                            values["targets"]!.Values<string>().SequenceEqual(["Two"]) &&
                            values.Value<string>("legacy") == "keep" && values["injected"] is null,
                "Custom settings save did not validate schema fields or preserve unknown historical values.");

            _ = catalog.SaveProjectCommonSettings("Fixture Group", 1, "Disabled", false, true);
            var common = catalog.GetProjectCommonSettings("Fixture Group", 1);
            context.Require(common.Status == "Disabled" && common.AllowJsNotification == false && common.AllowJsHttp &&
                            common.HttpAllowedUrls.SequenceEqual(["https://example.com/api"]),
                "Common settings did not preserve upstream HTTP hash and notification semantics.");

            _ = catalog.SaveGroupConfig("Fixture Group", JObject.FromObject(new
            {
                pathingConfig = new { partyName = "Updated", hideOnRepeat = true },
                enableShellConfig = true
            }));
            var config = catalog.GetGroupConfig("Fixture Group");
            context.Require(config["pathingConfig"]?.Value<string>("partyName") == "Updated" &&
                            config["pathingConfig"]?.Value<int>("distance") == 45 &&
                            config.Value<bool>("enableShellConfig") &&
                            catalog.List().Single().HideOnRepeat,
                "Group settings patch did not preserve unedited upstream fields.");
            var fightStrategies =
                config["pathingOptions"]?["fightStrategies"] as JArray ?? [];
            var onlyPickEliteDropsModes =
                config["pathingOptions"]?["onlyPickEliteDropsModes"] as JArray ?? [];
            context.Require(
                config["pathingConfig"]?["autoEatConfig"]?
                    .Value<string>("defaultAtkBoostingDishName") == "仙跳墙" &&
                config["pathingConfig"]?["autoFightConfig"]?
                    .Value<string>("onlyPickEliteDropsMode") ==
                        "DisableAutoPickupForNonElite" &&
                config["pathingConfig"]?["autoFightConfig"]?
                    .Value<int>("battleThresholdForLoot") == 3 &&
                config["pathingConfig"]?["autoFightConfig"]?
                    ["finishDetectConfig"]?.Value<bool>("fastCheckEnabled") == true &&
                fightStrategies.Values<string>().Contains("Farming") &&
                onlyPickEliteDropsModes.OfType<JObject>().Any(option =>
                        option.Value<string>("value") ==
                            "DisableAutoPickupForNonElite"),
                "Group settings omitted upstream AutoFight, AutoEat or option semantics.");

            _ = catalog.Create("Created Group");
            _ = catalog.Copy("Fixture Group", "Fixture Copy");
            context.Require(
                catalog.List().OrderBy(group => group.Index).Select(group => group.Name)
                    .SequenceEqual(["Fixture Group", "Created Group", "Fixture Copy"]) &&
                catalog.Get("Fixture Copy").Document["projects"]?.Count() == 1,
                "Script-group create/copy did not preserve upstream ordering or deep-copy the group.");
            _ = catalog.SetNextProject("Fixture Copy", 1);
            _ = catalog.Rename("Fixture Copy", "Renamed Copy");
            context.Require(
                !catalog.List().Any(group => group.Name == "Fixture Copy") &&
                catalog.List().Single(group => group.Name == "Renamed Copy")
                    .Projects.Single().NextFlag,
                "Script-group rename did not preserve the selected next project.");
            _ = catalog.Delete("Renamed Copy");
            _ = catalog.Delete("Created Group");
            context.Require(
                catalog.List().Select(group => (group.Name, group.Index))
                    .SequenceEqual([("Fixture Group", 1)]) &&
                !File.Exists(layout.SchedulerStatePath),
                "Script-group delete did not reindex groups or clear stale next-project state.");

            _ = catalog.AddProjects("Fixture Group", "Shell", [], "printf fixture");
            _ = catalog.Reverse("Fixture Group");
            var reversed = catalog.List().Single().Projects;
            context.Require(reversed.Count == 2 && reversed[0].Type == "Shell" && reversed[0].Index == 1,
                "Project add/reverse did not preserve upstream ordering and indexes.");
            _ = catalog.SetNextProject("Fixture Group", 2);
            context.Require(catalog.List().Single().Projects.Single(project => project.Index == 2).NextFlag,
                "Next-run project marker was not exposed by the Core summary.");
            var resumed = BetterGenshinImpact.Core.Script.Group.ScriptGroup.FromJson(
                await File.ReadAllTextAsync(
                    Path.Combine(layout.ScriptGroupPath, "Fixture Group.json"),
                    cancellationToken));
            ScriptGroupResumeState.ApplyAndConsume(layout, resumed);
            context.Require(
                resumed.Projects.Single(project => project.Index == 1).SkipFlag == true &&
                resumed.Projects.Single(project => project.Index == 2).SkipFlag != true &&
                !File.Exists(layout.SchedulerStatePath),
                "Shared script-group resume state did not skip preceding projects and consume the marker.");
        }
        finally
        {
            Global.StartUpPath = previousRoot;
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }
}
