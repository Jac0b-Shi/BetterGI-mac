using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoFight.Config;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Core.Config;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoFightRuntimePlatform : IAutoFightRuntimePlatform
{
    private readonly Func<ISystemInfo> _systemInfoProvider;
    private readonly MacImageRegionOcrService _recognition;
    private readonly ILoggerFactory _loggerFactory;

    public MacAutoFightRuntimePlatform(RuntimeLayout layout, Func<ISystemInfo> systemInfoProvider,
        MacImageRegionOcrService recognition, ILoggerFactory loggerFactory)
    {
        _systemInfoProvider = systemInfoProvider ?? throw new ArgumentNullException(nameof(systemInfoProvider));
        _recognition = recognition;
        _loggerFactory = loggerFactory;
        (AutoFightConfig, CombatMacroPriority) = LoadConfig(layout);
    }

    public ISystemInfo SystemInfo => _systemInfoProvider();
    public IOcrService OcrService => _recognition;
    public double DpiScale => TaskControlPlatform.Current.DpiScale;
    public AutoFightConfig AutoFightConfig { get; }
    public int CombatMacroPriority { get; }
    public ILogger<T> GetLogger<T>() => _loggerFactory.CreateLogger<T>();
    public BgiYoloPredictor CreateYoloPredictor(BgiOnnxModel model) => _recognition.CreateYoloPredictor(model);

    private static (AutoFightConfig Config, int CombatMacroPriority) LoadConfig(RuntimeLayout layout)
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path)) return (new AutoFightConfig(), 0);
        var root = JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip,
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
        return (
            root["autoFightConfig"]?.Deserialize<AutoFightConfig>(ConfigJson.Options) ?? new AutoFightConfig(),
            root["macroConfig"]?["combatMacroPriority"]?.GetValue<int>() ?? 0);
    }
}
