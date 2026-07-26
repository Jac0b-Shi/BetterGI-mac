using System;
using System.Threading;
using BetterGenshinImpact.GameTask.AutoSkip;

namespace BetterGenshinImpact.GameTask.AutoPathing;

/// <summary>
/// 剧情自动跳过会话。PathExecutor 检测到剧情界面后创建，
/// 每个识别帧调用一次 OnCapture 驱动跳过点击。
/// </summary>
public interface IPathExecutorAutoSkipSession
{
    void OnCapture(CaptureContent content);
}

/// <summary>
/// PathExecutor 的自动剧情能力边界。
/// Windows 组合提供基于 AutoSkipTrigger 的实现；
/// 尚未具备该能力的平台必须抛出结构化能力错误，不允许继续并伪装成功。
/// </summary>
public interface IPathExecutorAutoSkipPlatform
{
    IPathExecutorAutoSkipSession CreateSession();
}

public sealed class PathExecutorAutoSkipSessionFactory : IPathExecutorAutoSkipPlatform
{
    public IPathExecutorAutoSkipSession CreateSession() => new AutoSkipTriggerSession();

    private sealed class AutoSkipTriggerSession : IPathExecutorAutoSkipSession
    {
        private readonly AutoSkipTrigger _trigger = new(new AutoSkipConfig
        {
            Enabled = true,
            QuicklySkipConversationsEnabled = true,
            ClosePopupPagedEnabled = true,
            ClickChatOption = "优先选择最后一个选项",
        });

        public AutoSkipTriggerSession() => _trigger.Init();

        public void OnCapture(CaptureContent content) => _trigger.OnCapture(content);
    }
}

public static class PathExecutorAutoSkipPlatform
{
    private static IPathExecutorAutoSkipPlatform? _current;

    public static IPathExecutorAutoSkipPlatform Current => Volatile.Read(ref _current)
        ?? throw new InvalidOperationException("PathExecutor auto-skip platform has not been composed.");

    public static void Configure(IPathExecutorAutoSkipPlatform platform)
    {
        ArgumentNullException.ThrowIfNull(platform);
        if (Interlocked.CompareExchange(ref _current, platform, null) is not null)
            throw new InvalidOperationException("PathExecutor auto-skip platform has already been configured.");
    }
}
