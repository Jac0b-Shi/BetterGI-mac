using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.Core.Recognition.OCR;
using Newtonsoft.Json.Linq;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacGoToCraftingBenchRuntimePlatform(
    RuntimeLayout layout,
    IOcrService ocrService) : IGoToCraftingBenchRuntimePlatform
{
    private readonly RuntimeLayout _layout = layout ?? throw new ArgumentNullException(nameof(layout));

    public string SelectedConfigName => LoadSelectedConfigName(_layout);
    public IOcrService OcrService { get; } = ocrService ?? throw new ArgumentNullException(nameof(ocrService));

    public IReadOnlyList<CraftingBenchConfig> LoadConfigs()
    {
        var directory = Path.Combine(_layout.UserPath, "OneDragon");
        Directory.CreateDirectory(directory);
        return Directory.GetFiles(directory, "*.json")
            .Select(path => JObject.Parse(File.ReadAllText(path)))
            .Select(config => new CraftingBenchConfig(
                config.Value<string>("Name") ?? config.Value<string>("name") ?? string.Empty,
                config.Value<int?>("MinResinToKeep") ?? config.Value<int?>("minResinToKeep") ?? 0))
            .ToArray();
    }

    private static string LoadSelectedConfigName(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return string.Empty;
        var root = JObject.Parse(File.ReadAllText(path));
        return root.Value<string>("selectedOneDragonFlowConfigName") ?? string.Empty;
    }
}
