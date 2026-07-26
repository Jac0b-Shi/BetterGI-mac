using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.GameLoading;
using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.Extensions.Logging;
using Microsoft.Win32;
using Vanara.PInvoke;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsGameLoadingRuntimePlatform : IGameLoadingRuntimePlatform
{
    public GenshinStartConfig Config => TaskContext.Instance().Config.GenshinStartConfig;
    public ILogger<GameLoadingTrigger> Logger => App.GetLogger<GameLoadingTrigger>();
    public double DpiScale => TaskContext.Instance().DpiScale;

    public bool IsPlaytimeTrackingAvailable()
    {
        try
        {
            using var key = Registry.ClassesRoot.OpenSubKey("starward");
            return key?.GetValue("URL Protocol")?.ToString() == "";
        }
        catch (Exception exception)
        {
            Logger.LogDebug(exception, "检查 Starward 协议失败");
            return false;
        }
    }

    public bool TryStartPlaytimeTracking(string gameServer)
    {
        try
        {
            if (!IsPlaytimeTrackingAvailable()) return false;
            Process.Start(new ProcessStartInfo($"starward://playtime/{gameServer}")
            {
                UseShellExecute = true
            });
            return true;
        }
        catch (Exception exception)
        {
            Logger.LogDebug(exception, "Starward记录时间失败");
            return false;
        }
    }

    public string GetInstalledGameServer()
    {
        try
        {
            if (Registry.GetValue(@"HKEY_CURRENT_USER\Software\miHoYo\HYP\1_1\hk4e_cn",
                    "GameInstallPath", null) is string cn && !string.IsNullOrEmpty(cn))
                return "hk4e_cn";
            if (Registry.GetValue(@"HKEY_CURRENT_USER\Software\Cognosphere\HYP\1_0\hk4e_global",
                    "GameInstallPath", null) is string global && !string.IsNullOrEmpty(global))
                return "hk4e_global";
            if (Registry.GetValue(
                    @"HKEY_CURRENT_USER\Software\miHoYo\HYP\standalone\14_0\hk4e_cn\umfgRO5gh5\hk4e_cn",
                    "GameInstallPath", null) is string bilibili && !string.IsNullOrEmpty(bilibili))
                return "hk4e_bilibili";
        }
        catch (Exception exception)
        {
            Logger.LogDebug(exception, "获取服务器失败");
        }
        return "";
    }

    public BiliLoginWindowType GetBiliLoginWindowType()
    {
        using var process = Process.GetProcessesByName("YuanShen").FirstOrDefault();
        if (process is null) return BiliLoginWindowType.None;
        var result = BiliLoginWindowType.None;
        User32.EnumWindows((window, _) =>
        {
            try
            {
                var titleLength = User32.GetWindowTextLength(window);
                if (titleLength <= 0) return true;
                var title = new StringBuilder(titleLength + 1);
                User32.GetWindowText(window, title, title.Capacity);
                var text = title.ToString();
                if (!text.Contains("bilibili", StringComparison.OrdinalIgnoreCase)) return true;
                var owner = User32.GetWindow(window, User32.GetWindowCmd.GW_OWNER);
                if (owner == IntPtr.Zero) return true;
                User32.GetWindowThreadProcessId(owner, out var ownerPid);
                if (ownerPid != process.Id || !User32.IsWindowEnabled(window)) return true;
                if (text.Contains("协议", StringComparison.OrdinalIgnoreCase))
                    result = BiliLoginWindowType.Agreement;
                else if (text.Contains("登录", StringComparison.OrdinalIgnoreCase))
                    result = BiliLoginWindowType.Login;
                return result == BiliLoginWindowType.None;
            }
            catch (Exception exception)
            {
                Logger.LogDebug(exception, "枚举B服登录窗口失败");
                return true;
            }
        }, IntPtr.Zero);
        return result;
    }

    public void BackgroundClick() => TaskContext.Instance().PostMessageSimulator.LeftButtonClickBackground();
    public void MoveToGame1080P(double x, double y) => GameCaptureRegion.GameRegion1080PPosMove(x, y);
    public void ClickGame1080P(double x, double y) => GameCaptureRegion.GameRegion1080PPosClick(x, y);
}
