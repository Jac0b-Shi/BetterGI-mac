using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.Verification.Framework;
using Newtonsoft.Json.Linq;
using System.Runtime.Versioning;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class KeyBindingSettingsSuite : IVerificationSuite
{
    public string Name => "key-bindings";

    [SupportedOSPlatform("macos")]
    public async Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var root = Path.Combine(
            Path.GetTempPath(),
            $"bettergi-key-bindings-{Guid.NewGuid():N}");
        try
        {
            var layout = new RuntimeLayout(root);
            layout.EnsureCreated();
            await File.WriteAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"),
                """
                {
                  "preserved": {
                    "value": 42
                  },
                  "keyBindingsConfig": {
                    "globalKeyMappingEnabled": false,
                    "moveForward": 87
                  }
                }
                """,
                cancellationToken);

            var catalog = new KeyBindingSettingsCatalog(layout);
            var gameActions = new GameActionKeyResolver(layout);
            var externalKeys = new ExternalKeyMappingResolver(layout);
            var updateCount = 0;
            catalog.AttachUpdated(() =>
            {
                updateCount++;
                gameActions.Invalidate();
                externalKeys.Invalidate();
            });

            var settings = JObject.FromObject(catalog.Get());
            var bindings = (JArray)settings["bindings"]!;
            context.Require(
                bindings.Count == 46 &&
                settings["options"] is JArray { Count: > 60 } &&
                bindings.Single(item =>
                    item.Value<string>("id") == "moveForward")
                    .Value<int>("value") == 0x57 &&
                bindings.Single(item =>
                    item.Value<string>("id") == "pickUpOrInteract")
                    .Value<int>("value") == 0x46,
                "Core did not expose the complete upstream game-action binding catalog.");
            context.Require(
                externalKeys.Resolve("VK_W") is null,
                "External script keys were remapped while global mapping was disabled.");

            settings["globalKeyMappingEnabled"] = true;
            SetBinding(bindings, "moveForward", 0x45);
            SetBinding(bindings, "moveBackward", 0x01);
            SetBinding(bindings, "moveLeft", 0x00);
            SetBinding(bindings, "pickUpOrInteract", 0x47);
            SetBinding(bindings, "jump", 0x4A);
            var saved = JObject.FromObject(catalog.Save(settings));
            context.Require(
                updateCount == 1 &&
                saved.Value<bool>("globalKeyMappingEnabled") &&
                gameActions.Resolve(GIActions.MoveForward)
                    .WindowsVirtualKey == 0x45 &&
                externalKeys.Resolve("VK_W")?.WindowsVirtualKey == 0x45 &&
                externalKeys.Resolve("W")?.WindowsVirtualKey == 0x45 &&
                externalKeys.Resolve("VK_S")?.MouseButton == "left" &&
                externalKeys.Resolve("VK_A") is
                    { WindowsVirtualKey: null, MouseButton: null } &&
                externalKeys.Resolve("VK_LBUTTON") is null &&
                externalKeys.Resolve("VK_ESCAPE") is null,
                "Saved bindings did not hot-update built-in and external input with upstream semantics.");

            var persisted = JObject.Parse(await File.ReadAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"),
                cancellationToken));
            context.Require(
                persisted.SelectToken("preserved.value")?.Value<int>() == 42 &&
                persisted.SelectToken(
                    "keyBindingsConfig.pickUpOrInteract")?.Value<int>() ==
                    0x47 &&
                persisted.SelectToken(
                    "keyBindingsConfig.jump")?.Value<int>() == 0x4A,
                "Key binding save did not preserve unrelated configuration or configured actions.");

            var invalid = JObject.FromObject(catalog.Get());
            SetBinding((JArray)invalid["bindings"]!, "moveForward", 0xA1);
            var invalidValueRejected = false;
            try
            {
                _ = catalog.Save(invalid);
            }
            catch (ArgumentException)
            {
                invalidValueRejected = true;
            }
            context.Require(
                invalidValueRejected,
                "Key binding settings accepted a value unsupported by the macOS input bridge.");
        }
        finally
        {
            if (Directory.Exists(root))
                Directory.Delete(root, recursive: true);
        }
    }

    private static void SetBinding(
        JArray bindings,
        string id,
        int value)
    {
        var binding = (JObject)bindings.Single(item =>
            item.Value<string>("id") == id);
        binding["value"] = value;
    }
}
