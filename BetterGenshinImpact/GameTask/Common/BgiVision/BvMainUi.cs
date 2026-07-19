using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.AutoFight.Assets;
using BetterGenshinImpact.GameTask.Common.Element.Assets;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.GameTask.QuickTeleport.Assets;
using BetterGenshinImpact.Helpers;
using OpenCvSharp;
using System.Globalization;
using System.Linq;

namespace BetterGenshinImpact.GameTask.Common.BgiVision;

public static partial class Bv
{
    public static bool IsInMainUi(ImageRegion captureRa)
    {
        var culture = CultureInfo.GetCultureInfo(TaskParameterPlatform.Current.GameCultureInfoName);
        var revival = TaskParameterPlatform.Current.GetStringLocalizer<BvResxHelper>()
            .WithCultureGet(culture, "复苏");
        return IsInMainUi(
            captureRa,
            ElementAssets.Instance.PaimonMenuRo,
            AutoFightAssets.Instance.ConfirmRa,
            revival);
    }

    /// <summary>
    /// Shared main-UI recognition body. The Windows composition supplies the original
    /// ElementAssets/AutoFightAssets objects; the macOS composition builds the same
    /// recognition objects from its runtime asset root.
    /// </summary>
    public static bool IsInMainUi(
        ImageRegion captureRa,
        RecognitionObject paimonMenuRo,
        RecognitionObject reviveConfirmRo,
        string revivalText)
    {
        using var ra = captureRa.Find(paimonMenuRo);
        return ra.IsExist() && !IsInRevivePrompt(captureRa, reviveConfirmRo, revivalText);
    }

    internal static bool IsInRevivePrompt(
        ImageRegion region,
        RecognitionObject reviveConfirmRo,
        string revivalText)
    {
        using var confirmRectArea = region.Find(reviveConfirmRo);
        if (!confirmRectArea.IsEmpty())
        {
            var list = region.FindMulti(new RecognitionObject
            {
                RecognitionType = RecognitionTypes.Ocr,
                RegionOfInterest = new Rect(0, 0, region.Width, region.Height / 2)
            });

            if (list.Any(r => r.Text.Contains(revivalText)))
                return true;
        }

        return false;
    }

    /// <summary>
    /// 是否在大地图界面
    /// </summary>
    /// <param name="captureRa"></param>
    /// <returns></returns>
    public static bool IsInBigMapUi(ImageRegion captureRa)
    {
        using var scaleRa = captureRa.Find(QuickTeleportAssets.Instance.MapScaleButtonRo);
        if (scaleRa.IsExist())
        {
            return true;
        }

        using var settingsRa = captureRa.Find(QuickTeleportAssets.Instance.MapSettingsButtonRo);
        return settingsRa.IsExist();
    }

    public static bool IsInBlessingOfTheWelkinMoon(
        ImageRegion captureRa,
        RecognitionObject girlMoonRo,
        RecognitionObject welkinMoonRo)
    {
        using var girlRa = captureRa.Find(girlMoonRo);
        if (girlRa.IsExist())
            return true;
        using var moonRa = captureRa.Find(welkinMoonRo);
        return moonRa.IsExist();
    }
}
