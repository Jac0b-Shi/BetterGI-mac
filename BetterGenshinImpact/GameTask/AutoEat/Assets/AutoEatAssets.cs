using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Recognition.OpenCv;
using BetterGenshinImpact.GameTask.Model;
using OpenCvSharp;

namespace BetterGenshinImpact.GameTask.AutoEat.Assets;

public class AutoEatAssets : BaseAssets<AutoEatAssets>
{
    public RecognitionObject RecoveryIconRa;
    public RecognitionObject ResurrectionIconRa;

    #if BGI_FULL_WINDOWS
    private AutoEatAssets() : base()
    #else
    public static void Initialize(ISystemInfo systemInfo)
    {
        ArgumentNullException.ThrowIfNull(systemInfo);
        if (_instance is not null)
            throw new InvalidOperationException("AutoEatAssets is already initialized. Call DestroyInstance() first.");
        _instance = new AutoEatAssets(systemInfo);
    }

    public new static AutoEatAssets Instance => _instance
        ?? throw new InvalidOperationException("AutoEatAssets.Initialize(...) must be called before Instance.");

    public AutoEatAssets(ISystemInfo systemInfo) : base(systemInfo)
    #endif
    {
        var s = systemInfo.AssetScale;
        
        RecoveryIconRa = new RecognitionObject
        {
            Name = "RecoveryIcon",
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = GameTaskManager.LoadAssetImage("AutoEat", "Recovery.png"),
            Threshold = 0.8,
            RegionOfInterest = new Rect((int)(1810 * s), (int)(778 * s), (int)(23 * s), (int)(23 * s)),
            DrawOnWindow = false
        }.InitTemplate();

        ResurrectionIconRa = new RecognitionObject
        {
            Name = "ResurrectionIcon",
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = GameTaskManager.LoadAssetImage("AutoEat", "Resurrection.png"),
            Threshold = 0.8,
            RegionOfInterest = new Rect((int)(1810 * s), (int)(778 * s), (int)(18 * s), (int)(19 * s)),
            DrawOnWindow = false
        }.InitTemplate();
    }
}
