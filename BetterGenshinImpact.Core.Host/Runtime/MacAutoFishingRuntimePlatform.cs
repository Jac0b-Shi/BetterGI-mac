using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Infrastructure;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.Core.Recognition.ONNX;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Localization;
using Microsoft.Extensions.Logging;
using OpenCvSharp;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacAutoFishingRuntimePlatform : IAutoFishingRuntimePlatform
{
    private readonly RuntimeLayout _layout;
    private readonly Func<ISystemInfo> _systemInfoProvider;
    private readonly MacImageRegionOcrService _recognition;
    private readonly ILoggerFactory _loggerFactory;
    private readonly bool _screenshotUidCoverEnabled;
    private readonly object _configLock = new();
    private AutoFishingConfig _config;

    public MacAutoFishingRuntimePlatform(
        RuntimeLayout layout,
        Func<ISystemInfo> systemInfoProvider,
        MacImageRegionOcrService recognition,
        ILoggerFactory loggerFactory)
    {
        _layout = layout;
        _systemInfoProvider = systemInfoProvider ?? throw new ArgumentNullException(nameof(systemInfoProvider));
        _recognition = recognition;
        _loggerFactory = loggerFactory;
        (_config, GameCultureInfoName, _screenshotUidCoverEnabled) = LoadConfig();
    }

    public ISystemInfo SystemInfo => _systemInfoProvider();
    public AutoFishingConfig Config => Volatile.Read(ref _config);
    public string GameCultureInfoName { get; }
    public IOcrService OcrService => _recognition;
    public ILogger<T> GetLogger<T>() => _loggerFactory.CreateLogger<T>();
    public IStringLocalizer<T> GetStringLocalizer<T>() => new EmbeddedResourceStringLocalizer<T>();
    public BgiYoloPredictor CreateYoloPredictor(BgiOnnxModel model) =>
        _recognition.CreateYoloPredictor(model);
    public bool IsGameActive(out string activeProcessName)
    {
        TaskControlPlatform.Current.EnsureGameActive();
        activeProcessName = SystemInfo.GameProcessName;
        return true;
    }
    public ImageRegion? CaptureFrame() => TaskControlPlatform.Current.CaptureToRectArea(forceNew: true);
    public void DisableRealtimeFishing()
    {
        lock (_configLock)
        {
            var config = CloneConfig(Config);
            config.Enabled = false;
            PersistConfig(config);
            Volatile.Write(ref _config, config);
        }
    }
    public void UpdateConfig(AutoFishingConfig config) =>
        Volatile.Write(ref _config, CloneConfig(config));
    public Task SetTimeAsync(int hour, int minute, CancellationToken cancellationToken) =>
        new SetTimeTask().Start(hour, minute, cancellationToken);
    public void SaveBehaviourScreenshot(ImageRegion imageRegion, string fileName)
    {
        ArgumentNullException.ThrowIfNull(imageRegion);
        var safeName = Path.GetFileName(fileName);
        if (string.IsNullOrWhiteSpace(safeName) || safeName != fileName)
            throw new ArgumentException("Screenshot file name must not contain a path.", nameof(fileName));
        var directory = Path.Combine(_layout.RootPath, "log", "screenshot");
        Directory.CreateDirectory(directory);
        using var image = imageRegion.SrcMat.Clone();
        if (_screenshotUidCoverEnabled)
            ScreenshotPrivacy.ApplyUidCover(image, SystemInfo.ScaleTo1080PRatio);
        var path = Path.Combine(directory, safeName);
        if (!Cv2.ImWrite(path, image))
            throw new IOException($"OpenCV failed to save AutoFishing screenshot '{safeName}'.");
    }

    private (AutoFishingConfig Config, string Culture, bool ScreenshotUidCoverEnabled) LoadConfig()
    {
        var path = Path.Combine(_layout.UserPath, "config.json");
        if (!File.Exists(path)) return (new AutoFishingConfig(), "zh-Hans", true);
        var root = JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip,
        }) as JsonObject ?? throw new InvalidDataException("User/config.json root must be an object.");
        var config = root["autoFishingConfig"]?.Deserialize<AutoFishingConfig>(ConfigJson.Options)
            ?? new AutoFishingConfig();
        var culture = root["otherConfig"]?["gameCultureInfoName"]?.GetValue<string>() ?? "zh-Hans";
        var uidCover = root["commonConfig"]?["screenshotUidCoverEnabled"]?.GetValue<bool>() ?? true;
        _ = System.Globalization.CultureInfo.GetCultureInfo(culture);
        return (config, culture, uidCover);
    }

    private void PersistConfig(AutoFishingConfig config)
    {
        var path = Path.Combine(_layout.UserPath, "config.json");
        var root = File.Exists(path)
            ? JsonNode.Parse(File.ReadAllText(path), documentOptions: new JsonDocumentOptions
              {
                  AllowTrailingCommas = true,
                  CommentHandling = JsonCommentHandling.Skip,
              }) as JsonObject
                ?? throw new InvalidDataException("User/config.json root must be an object.")
            : new JsonObject();
        root["autoFishingConfig"] = JsonSerializer.SerializeToNode(config, ConfigJson.Options);
        Directory.CreateDirectory(_layout.UserPath);
        var temporaryPath = path + ".tmp";
        File.WriteAllText(temporaryPath, root.ToJsonString(ConfigJson.Options));
        File.Move(temporaryPath, path, overwrite: true);
    }

    private static AutoFishingConfig CloneConfig(AutoFishingConfig config) =>
        JsonSerializer.Deserialize<AutoFishingConfig>(
            JsonSerializer.Serialize(config, ConfigJson.Options), ConfigJson.Options)
        ?? throw new InvalidDataException("Failed to clone AutoFishingConfig.");
}
