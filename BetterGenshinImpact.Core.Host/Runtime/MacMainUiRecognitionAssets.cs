using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Recognition.OpenCv;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Model;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>The exact two upstream recognition objects required by Bv.IsInMainUi.</summary>
public sealed class MacMainUiRecognitionAssets : IDisposable
{
    public MacMainUiRecognitionAssets(ISystemInfo systemInfo)
    {
        var captureRect = systemInfo.ScaleMax1080PCaptureRect;
        PaimonMenu = new RecognitionObject
        {
            Name = "PaimonMenu",
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = Load(systemInfo, "Common/Element", "paimon_menu.png"),
            RegionOfInterest = new Rect(0, 0, captureRect.Width / 4, captureRect.Height / 4),
            DrawOnWindow = false
        }.InitTemplate();
        ReviveConfirm = new RecognitionObject
        {
            Name = "Confirm",
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = Load(systemInfo, "AutoFight", "confirm.png"),
            RegionOfInterest = new Rect(
                captureRect.Width / 2, captureRect.Height / 2,
                captureRect.Width / 2, captureRect.Height / 2),
            DrawOnWindow = false
        }.InitTemplate();
        GirlMoon = Template(systemInfo, "GameLoading", "girl_moon.png",
            new Rect(0, captureRect.Height / 2, captureRect.Width, captureRect.Height / 2), "GirlMoon");
        WelkinMoon = Template(systemInfo, "GameLoading", "welkin_moon_logo.png",
            new Rect(0, captureRect.Height / 2, captureRect.Width, captureRect.Height / 2), "WelkinMoon");
        Primogem = Template(systemInfo, "Common/Element", "primogem.png",
            new Rect(0, captureRect.Height / 3, captureRect.Width, captureRect.Height / 3), "Primogem");
    }

    public RecognitionObject PaimonMenu { get; }
    public RecognitionObject ReviveConfirm { get; }
    public RecognitionObject GirlMoon { get; }
    public RecognitionObject WelkinMoon { get; }
    public RecognitionObject Primogem { get; }

    public void Dispose()
    {
        Dispose(PaimonMenu);
        Dispose(ReviveConfirm);
        Dispose(GirlMoon);
        Dispose(WelkinMoon);
        Dispose(Primogem);
    }

    private static Mat Load(ISystemInfo systemInfo, string feature, string name) =>
        GameTaskManager.LoadAssetImage(feature, name, systemInfo);

    private static RecognitionObject Template(
        ISystemInfo systemInfo, string feature, string name, Rect roi, string objectName) =>
        new RecognitionObject
        {
            Name = objectName,
            RecognitionType = RecognitionTypes.TemplateMatch,
            TemplateImageMat = Load(systemInfo, feature, name),
            RegionOfInterest = roi,
            DrawOnWindow = false
        }.InitTemplate();

    private static void Dispose(RecognitionObject recognitionObject)
    {
        recognitionObject.MaskMat?.Dispose();
        recognitionObject.TemplateImageGreyMat?.Dispose();
        recognitionObject.TemplateImageMat?.Dispose();
    }
}
