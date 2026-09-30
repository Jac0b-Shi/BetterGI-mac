using System;

namespace BetterGenshinImpact.GameTask.AutoCombo;

/// <summary>共享任务的展示快照；Mac Host 通过 RPC 提供给 Swift，Windows 继续使用原浮窗。</summary>
public static class AutoComboPresentation
{
    private static readonly object Gate = new();
    private static string _tree = "";
    private static string _fallbackTree = "";
    private static bool _visible;
    public static string Tree
    {
        set
        {
            lock (Gate) _tree = value;
#if !BGI_PLATFORM_MAC
            ViewModel.Windows.AutoComboTreeViewModel.Instance.LatestTreeAscii = value;
#endif
        }
    }
    public static string FallbackTree
    {
        set
        {
            lock (Gate) _fallbackTree = value;
#if !BGI_PLATFORM_MAC
            ViewModel.Windows.AutoComboTreeViewModel.Instance.LatestFallbackTreeAscii = value;
#endif
        }
    }
    public static void Show()
    {
        lock (Gate) _visible = true;
#if !BGI_PLATFORM_MAC
        AutoComboTreeWindowService.Instance.Show();
#endif
    }
    public static void Hide()
    {
        lock (Gate) _visible = false;
#if !BGI_PLATFORM_MAC
        AutoComboTreeWindowService.Instance.Hide();
#endif
    }
    public static object Snapshot()
    {
        lock (Gate) return new { visible = _visible, tree = _tree, fallbackTree = _fallbackTree };
    }
}
