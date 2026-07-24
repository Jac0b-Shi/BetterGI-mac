using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Verification.Framework;
using Newtonsoft.Json.Linq;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class OneDragonCatalogSuite : IVerificationSuite
{
    public string Name => "one-dragon-catalog";

    public Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var root = Path.Combine(
            Path.GetTempPath(),
            $"bettergi-one-dragon-{Guid.NewGuid():N}");
        try
        {
            var layout = new RuntimeLayout(root);
            var catalog = new OneDragonCatalog(layout);

            var initial = catalog.List();
            context.Require(
                initial.Count == 1 &&
                initial[0].Name == "默认配置" &&
                initial[0].TaskCount == 8 &&
                initial[0].EnabledTaskCount == 0 &&
                initial[0].Selected,
                "OneDragon catalog did not create the upstream default task list.");
            context.Require(
                catalog.Get("默认配置").BuiltInTaskNames.SequenceEqual(
                [
                    "领取邮件",
                    "合成树脂",
                    "自动秘境",
                    "自动首领讨伐",
                    "自动幽境危战",
                    "自动地脉花",
                    "领取每日奖励",
                    "领取尘歌壶奖励",
                ]),
                "OneDragon catalog did not expose the upstream built-in task options.");
            var summaryPayload = JArray.FromObject(initial);
            var documentPayload = JObject.FromObject(catalog.Get("默认配置"));
            context.Require(
                summaryPayload[0]?["name"]?.Value<string>() == "默认配置" &&
                summaryPayload[0]?["selected"]?.Value<bool>() == true &&
                summaryPayload[0]?["Name"] is null &&
                documentPayload["builtInTaskNames"] is JArray &&
                documentPayload["tasks"]?[0]?["isEnabled"]?.Value<bool>() == false &&
                documentPayload["Tasks"] is null,
                "OneDragon RPC DTOs do not preserve the Swift camel-case contract.");

            var created = catalog.Create("夜班");
            context.Require(
                catalog.List().Single(item => item.Name == "夜班").Selected,
                "OneDragon catalog did not expose the selected config.");
            var firstTask = created.Tasks[0];
            var edited = (JObject)created.Config.DeepClone();
            edited["TaskEnabledList"]![firstTask.Id] = true;
            edited["FutureUpstreamSetting"] = new JObject
            {
                ["enabled"] = true,
                ["mode"] = "future",
            };
            var saved = catalog.Save("夜班", edited);
            context.Require(
                saved.Tasks.Single(task => task.Id == firstTask.Id).IsEnabled &&
                saved.Config["FutureUpstreamSetting"]?["mode"]?.Value<string>()
                    == "future",
                "OneDragon catalog did not preserve task state and unknown fields.");

            var renamed = catalog.Rename("夜班", "每日");
            context.Require(
                renamed.Name == "每日" &&
                renamed.Config["FutureUpstreamSetting"]?["enabled"]?.Value<bool>()
                    == true &&
                !File.Exists(Path.Combine(layout.OneDragonPath, "夜班.json")) &&
                File.Exists(Path.Combine(layout.OneDragonPath, "每日.json")),
                "OneDragon catalog rename did not preserve the document atomically.");

            var selectedRoot = JsonNode.Parse(
                File.ReadAllText(Path.Combine(layout.UserPath, "config.json")))
                as JsonObject;
            context.Require(
                selectedRoot?["selectedOneDragonFlowConfigName"]?.GetValue<string>()
                    == "每日",
                "OneDragon catalog did not update the selected config name.");

            catalog.Select("默认配置");
            context.Require(
                catalog.List().Single(item => item.Name == "默认配置").Selected,
                "OneDragon catalog did not persist an explicit config selection.");

            _ = catalog.Delete("每日");
            context.Require(
                catalog.List().Count == 1 &&
                !Directory.EnumerateFiles(
                    layout.OneDragonPath,
                    "*.tmp",
                    SearchOption.TopDirectoryOnly).Any(),
                "OneDragon catalog delete left an invalid or temporary config behind.");

            var rejectedTraversal = false;
            try
            {
                _ = catalog.Create("../escape");
            }
            catch (ArgumentException)
            {
                rejectedTraversal = true;
            }
            context.Require(
                rejectedTraversal,
                "OneDragon catalog accepted a path-traversal config name.");
        }
        finally
        {
            if (Directory.Exists(root))
                Directory.Delete(root, true);
        }

        return Task.CompletedTask;
    }
}
