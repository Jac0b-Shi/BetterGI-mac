using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Verification.Framework;
using System.Text;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class ScriptRepositorySuite : IVerificationSuite
{
    public string Name => "script-repository";

    public async Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        var root = Path.Combine(Path.GetTempPath(), $"bettergi-script-repository-{Guid.NewGuid():N}");
        try
        {
            var layout = new RuntimeLayout(root);
            layout.EnsureCreated();
            var repository = Path.Combine(root, "Repos", "bettergi-scripts-list");
            var repositoryContent = Path.Combine(repository, "repo");
            var sourceScript = Path.Combine(repositoryContent, "js", "Fixture");
            var sourcePathing = Path.Combine(repositoryContent, "pathing", "Fixture Routes");
            Directory.CreateDirectory(Path.Combine(sourceScript, "settings"));
            Directory.CreateDirectory(sourcePathing);
            Directory.CreateDirectory(Path.Combine(repositoryContent, "packages"));
            await File.WriteAllTextAsync(Path.Combine(repository, "repo.json"), """
                {
                  "indexes": [
                    {
                      "name": "js",
                      "type": "directory",
                      "children": [{
                        "name": "Fixture",
                        "type": "directory",
                        "version": "2.0.0",
                        "author": "BetterGI",
                        "description": "Repository fixture",
                        "tags": ["fixture"],
                        "children": []
                      }]
                    },
                    {
                      "name": "pathing",
                      "type": "directory",
                      "children": [{
                        "name": "Fixture Routes",
                        "type": "directory",
                        "children": [{
                          "name": "route.json",
                          "type": "file"
                        }]
                      }]
                    }
                  ]
                }
                """, cancellationToken);
            await File.WriteAllTextAsync(Path.Combine(sourceScript, "manifest.json"), """
                {
                  "manifest_version": 1,
                  "name": "Fixture",
                  "version": "2.0.0",
                  "main": "main.js",
                  "saved_files": ["settings/*.json"]
                }
                """, cancellationToken);
            await File.WriteAllTextAsync(
                Path.Combine(sourceScript, "main.js"),
                "import helper from 'packages/shared.js'; helper();",
                cancellationToken);
            await File.WriteAllTextAsync(
                Path.Combine(repositoryContent, "packages", "shared.js"),
                "export default function helper() {}",
                cancellationToken);
            await File.WriteAllTextAsync(
                Path.Combine(sourcePathing, "route.json"),
                """{"info":{"name":"updated route"},"positions":[]}""",
                cancellationToken);
            var webIndex = Path.Combine(root, "Assets", "Web", "ScriptRepo", "index.html");
            Directory.CreateDirectory(Path.GetDirectoryName(webIndex)!);
            await File.WriteAllTextAsync(webIndex, "<html>repository</html>", cancellationToken);

            var installedScript = Path.Combine(layout.UserPath, "JsScript", "Fixture");
            Directory.CreateDirectory(Path.Combine(installedScript, "settings"));
            await File.WriteAllTextAsync(
                Path.Combine(installedScript, "settings", "user.json"),
                """{"keep":true}""",
                cancellationToken);
            await File.WriteAllTextAsync(
                Path.Combine(installedScript, "main.js"),
                "old content",
                cancellationToken);

            var catalog = new ScriptRepositoryCatalog(layout);
            await File.WriteAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"),
                """
                {
                  "scriptConfig": {
                    "autoUpdateSubscribedScripts": false,
                    "autoUpdateBeforeCommandLineRun": false,
                    "selectedChannelName": "CNB",
                    "customRepoUrl": ""
                  }
                }
                """,
                cancellationToken);
            var automatic = await catalog.AutoUpdateSubscribedAsync(
                commandLineRun: false, cancellationToken);
            context.Require(
                automatic.AttemptedCount == 0,
                "Disabled subscription auto-update attempted repository work.");
            context.Require(
                catalog.GetRepoJson().Contains("\"Fixture\"", StringComparison.Ordinal),
                "Repository Web bridge did not return the upstream index.");
            context.Require(
                catalog.GetFile("js/Fixture/main.js").Contains("packages/shared.js", StringComparison.Ordinal),
                "Repository Web bridge did not return repository files.");

            var payload = Uri.EscapeDataString(Convert.ToBase64String(
                Encoding.UTF8.GetBytes("""["js/Fixture"]""")));
            var importUri = $"bettergi://script?import={payload}";
            var ignoredClipboard = catalog.InspectImportUri(
                "https://example.com/not-a-subscription");
            var clipboardPreview = catalog.InspectImportUri(importUri);
            context.Require(
                !ignoredClipboard.Recognized &&
                ignoredClipboard.Paths.Count == 0 &&
                clipboardPreview.Recognized &&
                clipboardPreview.Paths.SequenceEqual(["js/Fixture"]),
                "Clipboard subscription inspection did not preserve the upstream URI gate.");
            var result = await catalog.ImportUriAsync(
                importUri,
                cancellationToken);
            context.Require(result.InstalledCount == 1 && result.SubscribedPaths.SequenceEqual(["js/Fixture"]),
                "Repository Web import did not persist the selected subscription.");
            context.Require(
                await File.ReadAllTextAsync(Path.Combine(installedScript, "settings", "user.json"), cancellationToken)
                    == """{"keep":true}""",
                "Repository install did not preserve manifest saved_files.");
            context.Require(
                File.Exists(Path.Combine(installedScript, "packages", "shared.js")),
                "Repository install did not copy referenced package dependencies.");
            context.Require(
                (await File.ReadAllTextAsync(Path.Combine(installedScript, "main.js"), cancellationToken))
                    .Contains("packages/shared.js", StringComparison.Ordinal),
                "Repository install did not replace the script payload.");
            var installedProject = new ScriptProjectCatalog(layout).GetCode("Fixture");
            context.Require(
                installedProject.Name == "Fixture" &&
                installedProject.Code.Contains("packages/shared.js", StringComparison.Ordinal),
                "Installed script code was not available through the Core-owned project catalog.");

            await File.WriteAllTextAsync(
                Path.Combine(sourceScript, "main.js"),
                "import helper from 'packages/shared.js'; helper(); // updated",
                cancellationToken);
            var subscriptionPath = Path.Combine(
                layout.UserPath, "Subscriptions", "bettergi-scripts-list.json");
            await File.WriteAllTextAsync(
                subscriptionPath,
                """["js/Fixture","js/Ghost","pathing"]""",
                cancellationToken);
            await File.WriteAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"),
                """
                {
                  "scriptConfig": {
                    "autoUpdateSubscribedScripts": true,
                    "autoUpdateBeforeCommandLineRun": false,
                    "selectedChannelName": "GitHub",
                    "customRepoUrl": ""
                  }
                }
                """,
                cancellationToken);
            automatic = await catalog.AutoUpdateSubscribedAsync(
                commandLineRun: true, cancellationToken);
            context.Require(
                automatic.AttemptedCount == 0,
                "Command-line subscription update ignored its dedicated wait gate.");
            var batch = await catalog.UpdateSubscribedAsync(cancellationToken);
            context.Require(
                batch.AttemptedCount == 2 &&
                batch.SuccessCount == 2 &&
                batch.FailureCount == 0 &&
                batch.SubscribedPaths.SequenceEqual(["js/Fixture", "pathing"]),
                "One-click subscription update did not expand top-level paths or clean ghost entries.");
            context.Require(
                (await File.ReadAllTextAsync(
                    Path.Combine(installedScript, "main.js"), cancellationToken))
                    .Contains("// updated", StringComparison.Ordinal) &&
                await File.ReadAllTextAsync(
                    Path.Combine(installedScript, "settings", "user.json"), cancellationToken)
                    == """{"keep":true}""",
                "One-click subscription update did not replace code while preserving saved_files.");
            context.Require(
                File.Exists(Path.Combine(
                    layout.UserPath, "AutoPathing", "Fixture Routes", "route.json")),
                "One-click subscription update did not safely expand a top-level pathing subscription.");

            var state = catalog.GetState();
            context.Require(
                state.Available &&
                state.WebIndexPath == webIndex &&
                state.SubscribedPaths.SequenceEqual(["js/Fixture", "pathing"]),
                "Repository state did not expose the Web frontend and persisted subscription.");
        }
        finally
        {
            if (Directory.Exists(root))
                Directory.Delete(root, true);
        }
    }
}
