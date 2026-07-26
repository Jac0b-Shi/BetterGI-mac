using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.Common;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Helpers;

public partial class AssertUtils
{
    public static void CheckGameResolution(string msg = "")
    {
        var rect = AutoFightRuntimePlatform.Current.SystemInfo.CaptureAreaRect;
        if (rect.Width * 9 == rect.Height * 16)
            return;

        TaskControl.Logger.LogError(
            "游戏窗口分辨率不是 16:9 ！当前分辨率为 {Width}x{Height} , 非 16:9 分辨率的游戏无法正常使用{Msg}功能 !",
            rect.Width, rect.Height, msg);
        throw new System.Exception("游戏窗口分辨率不是 16:9");
    }
}
