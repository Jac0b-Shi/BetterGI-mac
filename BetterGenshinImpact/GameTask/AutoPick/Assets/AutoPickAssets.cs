using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.Model.Assets;
using BetterGenshinImpact.Helpers;
using BetterGenshinImpact.Platform.Abstractions;
using OpenCvSharp;
using System;

namespace BetterGenshinImpact.GameTask.AutoPick.Assets;

public sealed class AutoPickAssets
{
    private static readonly AssetsCache<CacheKey, AutoPickAssets> Cache = new(
        static key => new AutoPickAssets(key.CaptureSize, key.PickKey));

    public BgiKey PickVk { get; private set; } = BgiKey.F;
    public RecognitionObject PickRo { get; private set; }
    public RecognitionObject ChatPickRo { get; private set; }

    private int CaptureHeight { get; }
    private double AssetScale { get; }

    private AutoPickAssets(CaptureSize captureSize, string pickKey)
    {
        CaptureHeight = captureSize.Height;
        AssetScale = captureSize.AssetScale;
        PickRo = RecognitionAssets.Get("AutoPick", "F", captureSize.Width, captureSize.Height);
        ChatPickRo = LoadCustomChatPickKey("F", captureSize);
        if (pickKey == "F")
        {
            return;
        }

        try
        {
            PickRo = LoadCustomPickKey(pickKey, captureSize);
            PickVk = BgiKeyMapper.ToKey(pickKey);
            ChatPickRo = LoadCustomChatPickKey(pickKey, captureSize);
        }
        catch
        {
            PickRo = RecognitionAssets.Get("AutoPick", "F", captureSize.Width, captureSize.Height);
            PickVk = BgiKey.F;
            ChatPickRo = LoadCustomChatPickKey("F", captureSize);
        }
    }

    public static AutoPickAssets Get(Region region, string pickKey) => Get(CaptureSize.From(region), pickKey);

    public static AutoPickAssets Get(int captureWidth, int captureHeight, string pickKey) =>
        Get(new CaptureSize(captureWidth, captureHeight), pickKey);

    private static AutoPickAssets Get(CaptureSize captureSize, string pickKey)
    {
        var normalizedPickKey = string.IsNullOrWhiteSpace(pickKey) ? "F" : pickKey.Trim().ToUpperInvariant();
        return Cache.Get(new CacheKey(captureSize, normalizedPickKey));
    }

    private RecognitionObject LoadCustomPickKey(string key, CaptureSize captureSize)
    {
        return new RecognitionObject
        {
            Name = key,
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = GameTaskManager.LoadAssetImage("AutoPick", key + ".png", captureSize.Width, captureSize.Height),
            RegionOfInterest = new Rect((int)(1090 * AssetScale),
                (int)(330 * AssetScale),
                (int)(60 * AssetScale),
                (int)(420 * AssetScale)),
            DrawOnWindow = false
        }.InitTemplate();
    }

    private RecognitionObject LoadCustomChatPickKey(string key, CaptureSize captureSize)
    {
        return new RecognitionObject
        {
            Name = "chatPick" + key,
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = GameTaskManager.LoadAssetImage("AutoPick", key + ".png", captureSize.Width, captureSize.Height),
            RegionOfInterest = new Rect((int)(1200 * AssetScale),
                (int)(350 * AssetScale),
                (int)(50 * AssetScale),
                CaptureHeight - (int)(220 * AssetScale) - (int)(350 * AssetScale)),
            DrawOnWindow = false
        }.InitTemplate();
    }

    private readonly record struct CacheKey(CaptureSize CaptureSize, string PickKey);
}
