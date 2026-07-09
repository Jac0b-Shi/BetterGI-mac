using System;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Helpers;
using BetterGenshinImpact.Platform.Abstractions;
using OpenCvSharp;
using System.Drawing;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.GameTask.AutoPick.Assets;

public class AutoPickAssets : BaseAssets<AutoPickAssets>
{
    private readonly ILogger<AutoPickAssets> _logger;

    // Template-only assets (no config dependency)
    public RecognitionObject FRo;
    public RecognitionObject ChatIconRo;
    public RecognitionObject SettingsIconRo;
    public RecognitionObject LRo;

    // Config-dependent assets — property-backed with instance-level guard
    private BgiKey _pickVk = BgiKey.F;
    private RecognitionObject? _pickRo;
    private RecognitionObject? _chatPickRo;
    private bool _configured;

    private static readonly object InitializationLock = new();

    // ── Singleton entry point ──

    /// <summary>
    /// Sole initialization entry point. Must be called once before any Instance access.
    /// </summary>
    public static void Initialize(ISystemInfo systemInfo, IAutoPickConfigProvider configProvider, ILogger<AutoPickAssets> logger)
    {
        ArgumentNullException.ThrowIfNull(systemInfo);
        ArgumentNullException.ThrowIfNull(configProvider);
        ArgumentNullException.ThrowIfNull(logger);
        lock (InitializationLock)
        {
            if (_instance != null)
                throw new InvalidOperationException(
                    "AutoPickAssets is already initialized. Call DestroyInstance() first.");

            var instance = new AutoPickAssets(systemInfo, logger);
            instance.Configure(configProvider);
            _instance = instance;
        }
    }

    /// <summary>
    /// Hidden static property. Does NOT fall back to Activator/parameterless constructor.
    /// Throws if <see cref="Initialize"/> has not been called.
    /// </summary>
    public new static AutoPickAssets Instance =>
        _instance ?? throw new InvalidOperationException(
            "AutoPickAssets.Initialize(...) must be called before Instance.");

    // ── Property guards ──

    private void EnsureThisConfigured()
    {
        if (!_configured)
            throw new InvalidOperationException(
                "AutoPickAssets has not been configured. Call Configure() before accessing config-dependent fields.");
    }

    public BgiKey PickVk { get { EnsureThisConfigured(); return _pickVk; } }
    public RecognitionObject PickRo { get { EnsureThisConfigured(); return _pickRo!; } }
    public RecognitionObject? ChatPickRo { get { EnsureThisConfigured(); return _chatPickRo; } }

    /// <summary>
    /// Static convenience: check the current singleton. Instance-level checks use <see cref="EnsureThisConfigured"/>.
    /// </summary>
    public static void EnsureConfigured() =>
        Instance.EnsureThisConfigured();

    // ── Constructors ──

    /// <summary>
    /// Parameterized ctor used by <see cref="Initialize"/>. Receives ISystemInfo and ILogger explicitly.
    /// </summary>
    private AutoPickAssets(ISystemInfo systemInfo, ILogger<AutoPickAssets> logger)
        : base(systemInfo)
    {
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        InitTemplateAssets();
    }

    private void InitTemplateAssets()
    {
        FRo = new RecognitionObject
        {
            Name = "F",
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = GameTaskManager.LoadAssetImage("AutoPick", "F.png", systemInfo),
            RegionOfInterest = new Rect((int)(1090 * AssetScale),
                (int)(330 * AssetScale),
                (int)(60 * AssetScale),
                (int)(420 * AssetScale)),
            DrawOnWindow = false
        }.InitTemplate();

        ChatIconRo = new RecognitionObject
        {
            Name = "ChatIcon",
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = GameTaskManager.LoadAssetImage("AutoSkip", "icon_option.png", systemInfo),
            DrawOnWindow = false,
#if BGI_FULL_WINDOWS
            DrawOnWindowPen = new Pen(Color.Chocolate, 2),
#endif
        }.InitTemplate();

        SettingsIconRo = new RecognitionObject
        {
            Name = "SettingsIcon",
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = GameTaskManager.LoadAssetImage("AutoPick", "icon_settings.png", systemInfo),
            DrawOnWindow = false,
#if BGI_FULL_WINDOWS
            DrawOnWindowPen = new Pen(Color.Chocolate, 2),
#endif
        }.InitTemplate();

        LRo = new RecognitionObject
        {
            Name = "L",
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = GameTaskManager.LoadAssetImage("AutoPick", "L.png", systemInfo),
            RegionOfInterest = new Rect(CaptureRect.Width-(int)(110 * AssetScale),
                (int)(550 * AssetScale),
                (int)(70 * AssetScale),
                (int)(100 * AssetScale)),
        }.InitTemplate();
    }

    // ── Configuration ──

    /// <summary>
    /// Single-use configuration. Any repeated Configure call throws.
    /// All config-dependent asset initialization (PickKey, PickVk, PickRo, ChatPickRo)
    /// happens here. On failure, falls back to F-key defaults and writes back PickKey="F".
    /// </summary>
    public void Configure(IAutoPickConfigProvider provider)
    {
        ArgumentNullException.ThrowIfNull(provider);
        if (_configured)
            throw new InvalidOperationException("AutoPickAssets is already configured.");

        var keyName = provider.AutoPickConfig.PickKey;

        if (string.IsNullOrEmpty(keyName))
        {
            // No custom key configured — defaults apply
            _pickRo = FRo;
            _pickVk = BgiKey.F;
            _chatPickRo = null;
            _configured = true;
            return;
        }

        try
        {
            _pickRo = LoadCustomPickKey(keyName);
            _pickVk = BgiKeyMapper.ToKey(keyName);
#if BGI_FULL_WINDOWS
            TaskContext.Instance().Config.KeyBindingsConfig.PickUpOrInteract = (Core.Config.KeyId)(int)_pickVk;
#endif
            _chatPickRo = LoadCustomChatPickKey(keyName);
        }
        catch (Exception e)
        {
            _logger.LogDebug(e, "加载自定义拾取按键时发生异常");
            _logger.LogError("加载自定义拾取按键失败，继续使用默认的F键");
            provider.AutoPickConfig.PickKey = "F";
            _pickRo = FRo;
            _pickVk = BgiKey.F;
            _chatPickRo = null;
            _configured = true; // configured to fallback state
            return;
        }

        if (keyName != "F")
        {
            _logger.LogInformation("自定义拾取按键：{Key}", keyName);
        }

        _configured = true;
    }

    // ── Load helpers ──

    public RecognitionObject LoadCustomPickKey(string key)
    {
        return new RecognitionObject
        {
            Name = key,
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = GameTaskManager.LoadAssetImage("AutoPick", key + ".png", systemInfo),
            RegionOfInterest = new Rect((int)(1090 * AssetScale),
                (int)(330 * AssetScale),
                (int)(60 * AssetScale),
                (int)(420 * AssetScale)),
            DrawOnWindow = false
        }.InitTemplate();
    }

    public RecognitionObject LoadCustomChatPickKey(string key)
    {
        return new RecognitionObject
        {
            Name = "chatPick" + key,
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = GameTaskManager.LoadAssetImage("AutoPick", key + ".png", systemInfo),
            RegionOfInterest = new Rect((int)(1200 * AssetScale),
                (int)(350 * AssetScale),
                (int)(50 * AssetScale),
                CaptureRect.Height - (int)(220 * AssetScale) - (int)(350 * AssetScale)),
            DrawOnWindow = false
        }.InitTemplate();
    }
}
