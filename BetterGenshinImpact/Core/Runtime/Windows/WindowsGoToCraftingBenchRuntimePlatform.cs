using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common.Job;
using Newtonsoft.Json;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsGoToCraftingBenchRuntimePlatform : IGoToCraftingBenchRuntimePlatform
{
    public string SelectedConfigName => TaskContext.Instance().Config.SelectedOneDragonFlowConfigName;
    public IOcrService OcrService => OcrFactory.Paddle;

    public IReadOnlyList<CraftingBenchConfig> LoadConfigs()
    {
        var directory = Global.Absolute(@"User\OneDragon");
        Directory.CreateDirectory(directory);
        return Directory.GetFiles(directory, "*.json")
            .Select(path => JsonConvert.DeserializeObject<OneDragonFlowConfig>(File.ReadAllText(path)))
            .Where(config => config is not null)
            .Select(config => new CraftingBenchConfig(config!.Name, config.MinResinToKeep))
            .ToArray();
    }
}
