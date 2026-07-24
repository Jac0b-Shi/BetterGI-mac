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
                initial[0].EnabledTaskCount == 0,
                "OneDragon catalog did not create the upstream default task list.");

            var created = catalog.Create("夜班");
            var firstTask = created.Tasks[0];
            var edited = (JObject)created.Config.DeepClone();
            edited["TaskEnabledList"]![firstTask.Id] = true;
            var saved = catalog.Save("夜班", edited);
            context.Require(
                saved.Tasks.Single(task => task.Id == firstTask.Id).IsEnabled,
                "OneDragon catalog did not persist enabled task state.");

            var renamed = catalog.Rename("夜班", "每日");
            context.Require(
                renamed.Name == "每日" &&
                !File.Exists(Path.Combine(layout.OneDragonPath, "夜班.json")) &&
                File.Exists(Path.Combine(layout.OneDragonPath, "每日.json")),
                "OneDragon catalog rename did not atomically replace the config path.");

            var selectedRoot = JsonNode.Parse(
                File.ReadAllText(Path.Combine(layout.UserPath, "config.json")))
                as JsonObject;
            context.Require(
                selectedRoot?["selectedOneDragonFlowConfigName"]?.GetValue<string>()
                    == "每日",
                "OneDragon catalog did not update the selected config name.");

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
