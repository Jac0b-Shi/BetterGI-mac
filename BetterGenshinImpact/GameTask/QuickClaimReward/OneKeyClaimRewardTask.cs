using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.Model;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.GameTask.QuickClaimReward;

public class OneKeyClaimRewardTask : Singleton<OneKeyClaimRewardTask>
{
    public const string ClickOnceMode = "点按一次";
    public const string HoldMode = "按住持续";

    private const int MaxClickCountPerRun = 30;
    private const int ScrollChunkSize = 10;
    private const int MaxBlankContinueChecks = 3;
    private const int ScrollRenderDelayMilliseconds = 120;

    private readonly object _taskLock = new();
    private CancellationTokenSource? _cts;
    private Task? _claimTask;
    private volatile bool _isKeyDown;
    private DateTime _lastNoRewardLogTime = DateTime.MinValue;

    public void RunHotKey(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        KeyDown();
        try
        {
            cancellationToken.WaitHandle.WaitOne();
        }
        finally
        {
            KeyUp();
        }
        cancellationToken.ThrowIfCancellationRequested();
    }

    public void KeyDown()
    {
        if (_isKeyDown)
        {
            return;
        }

        _isKeyDown = true;
        var platform = OneKeyClaimRewardRuntimePlatform.Current;
        if (!CanRun(platform))
        {
            return;
        }

        if (IsHoldMode(platform.Settings))
        {
            StartHoldTask(platform);
        }
        else
        {
            StartClickOnceTask(platform);
        }
    }

    public void KeyUp()
    {
        _isKeyDown = false;
        if (IsHoldMode(OneKeyClaimRewardRuntimePlatform.Current.Settings))
        {
            _cts?.Cancel();
        }
    }

    private static bool CanRun(IOneKeyClaimRewardRuntimePlatform platform)
    {
        if (!platform.IsInitialized)
        {
            platform.NotifyNotStarted();
            return false;
        }

        return platform.IsGameProcessActive;
    }

    private void StartClickOnceTask(IOneKeyClaimRewardRuntimePlatform platform)
    {
        lock (_taskLock)
        {
            if (_claimTask is { IsCompleted: false })
            {
                return;
            }

            _cts?.Dispose();
            var cancellation = new CancellationTokenSource();
            _cts = cancellation;
            _claimTask = Task.Run(
                () => ClaimCurrentPageAsync(platform, cancellation.Token));
        }
    }

    private void StartHoldTask(IOneKeyClaimRewardRuntimePlatform platform)
    {
        lock (_taskLock)
        {
            if (_claimTask is { IsCompleted: false })
            {
                return;
            }

            _cts?.Dispose();
            var cancellation = new CancellationTokenSource();
            _cts = cancellation;
            _claimTask = Task.Run(
                () => ClaimWhileHoldingAsync(platform, cancellation.Token));
        }
    }

    private async Task ClaimCurrentPageAsync(
        IOneKeyClaimRewardRuntimePlatform platform,
        CancellationToken cancellationToken)
    {
        try
        {
            var clickCount = 0;
            while (!cancellationToken.IsCancellationRequested &&
                   clickCount < MaxClickCountPerRun)
            {
                if (!await TryClaimOneRewardAsync(platform, cancellationToken))
                {
                    break;
                }

                clickCount++;
                await Delay(180, cancellationToken);
            }

            if (clickCount == 0)
            {
                platform.Logger.LogInformation(
                    "一键领取奖励：未找到领取图标");
            }
            else
            {
                platform.Logger.LogInformation(
                    "一键领取奖励：本次已点击 {Count} 个领取图标",
                    clickCount);
            }

            if (clickCount >= MaxClickCountPerRun)
            {
                platform.Logger.LogWarning(
                    "一键领取奖励：已达到单次点击上限 {Count}，请检查当前界面是否仍有可领取图标",
                    MaxClickCountPerRun);
            }
        }
        catch (OperationCanceledException)
            when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            platform.Logger.LogWarning(
                exception,
                "一键领取奖励执行异常: {Message}",
                exception.Message);
        }
    }

    private async Task ClaimWhileHoldingAsync(
        IOneKeyClaimRewardRuntimePlatform platform,
        CancellationToken cancellationToken)
    {
        platform.Logger.LogInformation("一键领取奖励：开始持续领取");
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                if (await TryClaimOneRewardAsync(platform, cancellationToken))
                {
                    await Delay(180, cancellationToken);
                    continue;
                }

                var settings = platform.Settings;
                if (CanScrollDown(settings))
                {
                    LogNoReward(
                        platform,
                        "一键领取奖励：未找到领取图标，滚轮下滑");
                    ScrollDown(
                        platform,
                        settings.ScrollDownAmount,
                        cancellationToken);
                    await Delay(
                        ScrollRenderDelayMilliseconds,
                        cancellationToken);
                }
                else
                {
                    LogNoReward(platform, "一键领取奖励：未找到领取图标");
                    await Delay(260, cancellationToken);
                }
            }
        }
        catch (OperationCanceledException)
            when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            platform.Logger.LogWarning(
                exception,
                "一键领取奖励持续执行异常: {Message}",
                exception.Message);
        }
        finally
        {
            platform.Logger.LogInformation("一键领取奖励：持续领取已停止");
        }
    }

    private static async Task<bool> TryClaimOneRewardAsync(
        IOneKeyClaimRewardRuntimePlatform platform,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        using var capture = platform.Capture(cancellationToken);
        var candidate = FindRewardCandidates(capture).FirstOrDefault();
        if (candidate is null)
        {
            return false;
        }

        platform.Click(candidate.Region, cancellationToken);
        platform.Logger.LogInformation(
            "一键领取奖励：点击{IconName}图标",
            candidate.Name);
        await PressEscIfBlankContinueShownAsync(
            platform,
            cancellationToken);
        return true;
    }

    private static List<RewardCandidate> FindRewardCandidates(
        ImageRegion capture)
    {
        var candidates = new List<RewardCandidate>();

        candidates.AddRange(
            capture.FindMulti(
                    RecognitionAssets.Get(
                        "QuickClaimReward", "ClaimText", capture))
                .Select(region => new RewardCandidate(region, "领取")));
        candidates.AddRange(
            capture.FindMulti(
                    RecognitionAssets.Get(
                        "QuickClaimReward", "ClaimGift", capture))
                .Select(region => new RewardCandidate(region, "礼物领取")));

        return
        [
            .. candidates
                .OrderBy(candidate => candidate.Region.Top)
                .ThenBy(candidate => candidate.Region.Left)
        ];
    }

    private static async Task PressEscIfBlankContinueShownAsync(
        IOneKeyClaimRewardRuntimePlatform platform,
        CancellationToken cancellationToken)
    {
        for (var index = 0; index < MaxBlankContinueChecks; index++)
        {
            await Delay(160, cancellationToken);

            using var capture = platform.Capture(cancellationToken);
            using var continueTip = capture.Find(
                RecognitionAssets.Get(
                    "QuickClaimReward",
                    "ClickBlankContinue",
                    capture));
            if (continueTip.IsEmpty())
            {
                continue;
            }

            platform.PressEscape(cancellationToken);
            platform.Logger.LogInformation(
                "一键领取奖励：检测到“点击空白区域继续”，已按 ESC");
            await Delay(220, cancellationToken);
            return;
        }
    }

    private void LogNoReward(
        IOneKeyClaimRewardRuntimePlatform platform,
        string message)
    {
        if ((DateTime.Now - _lastNoRewardLogTime).TotalSeconds < 2)
        {
            return;
        }

        _lastNoRewardLogTime = DateTime.Now;
        platform.Logger.LogInformation("{Message}", message);
    }

    internal static bool IsHoldMode(OneKeyClaimRewardSettings settings) =>
        settings.HotkeyMode == HoldMode;

    internal static bool CanScrollDown(OneKeyClaimRewardSettings settings) =>
        IsHoldMode(settings) && settings.ScrollDownEnabled;

    internal static void ScrollDown(
        IOneKeyClaimRewardRuntimePlatform platform,
        int configuredAmount,
        CancellationToken cancellationToken)
    {
        var amount = Math.Max(1, Math.Abs(configuredAmount));
        while (amount > 0)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var scrollAmount = Math.Min(amount, ScrollChunkSize);
            platform.VerticalScroll(-scrollAmount, cancellationToken);
            amount -= scrollAmount;
        }
    }

    private static Task Delay(
        int millisecondsDelay,
        CancellationToken cancellationToken) =>
        millisecondsDelay <= 0
            ? Task.CompletedTask
            : Task.Delay(millisecondsDelay, cancellationToken);

    private sealed record RewardCandidate(Region Region, string Name);
}
