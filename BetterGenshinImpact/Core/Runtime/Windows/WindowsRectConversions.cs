using BetterGenshinImpact.Platform.Abstractions;
using Vanara.PInvoke;

namespace BetterGenshinImpact.Core.Runtime.Windows;

/// <summary>Windows 系统矩形与共享平台矩形的无损转换边界。</summary>
public static class WindowsRectConversions
{
    public static RECT ToWindowsRect(this BgiRect rect) =>
        new(rect.X, rect.Y, rect.Right, rect.Bottom);

    public static BgiRect ToBgiRect(this RECT rect) =>
        new(rect.X, rect.Y, rect.Width, rect.Height);
}
