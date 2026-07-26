using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.AutoPick;

namespace BetterGenshinImpact.Core.Adapters;

/// <summary>
/// macOS runtime adapter providing AutoPick config and OCR config.
/// Receives configuration values explicitly — no reference to TaskContext, RunnerContext, or Windows APIs.
/// <para>
/// <c>AutoPickConfig</c> returns the same mutable reference passed at construction,
/// preserving upstream write-back semantics (e.g. <c>PickKey = "F"</c> on load failure).
/// </para>
/// </summary>
public sealed class MacCoreRuntimeAdapter : IAutoPickConfigProvider, IOcrRuntimeConfigProvider
{
    private readonly AutoPickConfig _autoPickConfig;
    private readonly PaddleOcrModelConfig _paddleModel;
    private readonly string _gameCultureInfoName;

    public MacCoreRuntimeAdapter(
        AutoPickConfig autoPickConfig,
        PaddleOcrModelConfig paddleModel,
        string gameCultureInfoName)
    {
        _autoPickConfig = autoPickConfig ?? throw new ArgumentNullException(nameof(autoPickConfig));
        _paddleModel = paddleModel;
        if (string.IsNullOrWhiteSpace(gameCultureInfoName))
            throw new ArgumentException("Game culture name must not be empty.", nameof(gameCultureInfoName));
        _gameCultureInfoName = gameCultureInfoName;
    }

    // IAutoPickConfigProvider
    public AutoPickConfig AutoPickConfig => _autoPickConfig;

    public void UpdateAutoPickConfig(AutoPickConfig config)
    {
        ArgumentNullException.ThrowIfNull(config);
        _autoPickConfig.Enabled = config.Enabled;
        _autoPickConfig.ItemIconLeftOffset = config.ItemIconLeftOffset;
        _autoPickConfig.ItemTextLeftOffset = config.ItemTextLeftOffset;
        _autoPickConfig.ItemTextRightOffset = config.ItemTextRightOffset;
        _autoPickConfig.OcrEngine = config.OcrEngine;
        _autoPickConfig.FastModeEnabled = config.FastModeEnabled;
        _autoPickConfig.PickKey = config.PickKey;
        _autoPickConfig.BlackListEnabled = config.BlackListEnabled;
        _autoPickConfig.WhiteListEnabled = config.WhiteListEnabled;
    }

    // IOcrRuntimeConfigProvider
    public PaddleOcrModelConfig PaddleModel => _paddleModel;
    public string GameCultureInfoName => _gameCultureInfoName;
}
