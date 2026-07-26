using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation.Exception;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.QuickSereniteaPot;

public class QuickSereniteaPotTask
{
    public static void Done(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var platform = QuickSereniteaPotRuntimePlatform.Current;
        if (!platform.IsInitialized)
        {
            platform.NotifyNotStarted();
            return;
        }
        if (!platform.IsGameProcessActive)
            return;

        try
        {
            platform.SimulateAction(
                GIActions.OpenInventory,
                cancellationToken);
            platform.Wait(500, cancellationToken);
            WaitForBagToOpen(platform, cancellationToken);

            platform.ClickGame1080P(1050, 50, cancellationToken);
            platform.Wait(200, cancellationToken);

            FindPotIcon(platform, cancellationToken);
            platform.Wait(200, cancellationToken);

            using (var capture = platform.Capture(
                       forceNew: false,
                       cancellationToken))
            {
                Bv.ClickWhiteConfirmButton(capture);
            }
            platform.Wait(800, cancellationToken);

            var success = false;
            for (var attempt = 0; attempt < 5; attempt++)
            {
                using var capture = platform.Capture(
                    forceNew: false,
                    cancellationToken);
                if (!Bv.IsInMainUi(capture))
                    continue;
                success = true;
                break;
            }

            if (!success)
            {
                for (var attempt = 0; attempt < 5; attempt++)
                {
                    using var capture = platform.Capture(
                        forceNew: false,
                        cancellationToken);
                    if (Bv.IsInBigMapUi(capture))
                        return;
                    platform.SimulateAction(
                        GIActions.OpenInventory,
                        cancellationToken);
                }
            }

            using var interactionCapture = platform.Capture(
                forceNew: false,
                cancellationToken);
            CompleteInteraction(
                platform,
                Bv.FindF(interactionCapture, "进入", "尘歌壶"),
                Bv.FindF(interactionCapture, "离开", "尘歌壶"),
                cancellationToken);
        }
        catch (OperationCanceledException)
            when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            platform.LogWarning(exception);
        }
        finally
        {
            platform.ClearOverlay();
        }
    }

    internal static void CompleteInteraction(
        IQuickSereniteaPotRuntimePlatform platform,
        bool isEnter,
        bool isLeave,
        CancellationToken cancellationToken)
    {
        if (!isEnter && !isLeave)
        {
            platform.LogInformation(
                "快速进出尘歌壶:未识别到 进入或离开尘歌壶");
            return;
        }

        var action = isEnter ? "进入" : "离开";
        platform.LogInformation(
            $"快速进出尘歌壶:识别到 {action}尘歌壶");
        platform.SimulateAction(
            GIActions.PickUpOrInteract,
            cancellationToken);
        platform.LogInformation(
            $"快速进出尘歌壶:F{action}尘歌壶");
        platform.Wait(200, cancellationToken);
        platform.ClickGame1080P(1010, 760, cancellationToken);
    }

    private static void WaitForBagToOpen(
        IQuickSereniteaPotRuntimePlatform platform,
        CancellationToken cancellationToken)
    {
        Retry(() =>
        {
            platform.Wait(1, cancellationToken);
            using var capture = platform.Capture(
                forceNew: true,
                cancellationToken);
            using var result = capture.Find(RecognitionAssets.Get(
                "QuickSereniteaPot",
                "BagCloseButton",
                capture));
            if (result.IsEmpty())
                throw new RetryException("背包未打开");
        }, platform, retryIntervalMilliseconds: 500, maxAttemptCount: 5,
            cancellationToken);
    }

    private static void FindPotIcon(
        IQuickSereniteaPotRuntimePlatform platform,
        CancellationToken cancellationToken)
    {
        Retry(() =>
        {
            platform.Wait(1, cancellationToken);
            using var capture = platform.Capture(
                forceNew: true,
                cancellationToken);
            using var result = capture.Find(RecognitionAssets.Get(
                "QuickSereniteaPot",
                "SereniteaPotIcon",
                capture));
            if (result.IsEmpty())
                throw new RetryException("未检测到壶");
            result.Click();
        }, platform, retryIntervalMilliseconds: 200, maxAttemptCount: 3,
            cancellationToken);
    }

    private static void Retry(
        Action action,
        IQuickSereniteaPotRuntimePlatform platform,
        int retryIntervalMilliseconds,
        int maxAttemptCount,
        CancellationToken cancellationToken)
    {
        RetryException? lastException = null;
        for (var attempt = 0; attempt < maxAttemptCount; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (attempt > 0)
                platform.Wait(retryIntervalMilliseconds, cancellationToken);
            try
            {
                action();
                return;
            }
            catch (RetryException exception)
            {
                lastException = exception;
            }
        }

        if (lastException is not null)
            throw lastException;
        throw new InvalidOperationException(
            "Retry ended without an attempt.");
    }
}
