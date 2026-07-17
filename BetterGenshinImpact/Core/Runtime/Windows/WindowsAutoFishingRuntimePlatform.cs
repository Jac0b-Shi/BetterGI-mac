using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoFishing;
using BetterGenshinImpact.GameTask.Model.Area;
using OpenCvSharp;
using System.Threading.Tasks;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsAutoFishingRuntimePlatform : IAutoFishingRuntimePlatform
{
    public void SaveBehaviourScreenshot(ImageRegion imageRegion, string fileName)
    {
        var savePath = Global.Absolute(@$"log\screenshot\{fileName}");
        var mat = imageRegion.SrcMat;
        if (TaskContext.Instance().Config.CommonConfig.ScreenshotUidCoverEnabled)
        {
            _ = Task.Run(() =>
            {
                using var copy = mat.Clone();
                var assetScale = TaskContext.Instance().SystemInfo.ScaleTo1080PRatio;
                var rect = new Rect(
                    (int)(copy.Width - MaskWindowConfig.UidCoverRightBottomRect.X * assetScale),
                    (int)(copy.Height - MaskWindowConfig.UidCoverRightBottomRect.Y * assetScale),
                    (int)(MaskWindowConfig.UidCoverRightBottomRect.Width * assetScale),
                    (int)(MaskWindowConfig.UidCoverRightBottomRect.Height * assetScale));
                copy.Rectangle(rect, Scalar.White, -1);
                Cv2.ImWrite(savePath, copy);
            });
        }
        else
        {
            _ = Task.Run(() => Cv2.ImWrite(savePath, mat));
        }
    }
}
