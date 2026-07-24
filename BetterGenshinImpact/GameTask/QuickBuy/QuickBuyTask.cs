using BetterGenshinImpact.Core.Recognition;
using System;
using System.Threading;

namespace BetterGenshinImpact.GameTask.QuickBuy;

public class QuickBuyTask
{
    public static void Done(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var platform = QuickBuyRuntimePlatform.Current;
        if (!platform.IsInitialized)
        {
            platform.NotifyNotStarted();
            return;
        }
        if (!platform.IsGameProcessActive)
        {
            return;
        }

        try
        {
            using var capture = platform.Capture();
            var isSereniteaPot = capture.Find(
                RecognitionAssets.Get(
                    "QuickBuy", "SereniteaPotCoin", capture)).IsExist();
            Execute(platform, isSereniteaPot, cancellationToken);
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

    internal static void Execute(
        IQuickBuyRuntimePlatform platform,
        bool isSereniteaPot,
        CancellationToken cancellationToken)
    {
        if (isSereniteaPot)
        {
            platform.MoveGame1080P(1450, 690, cancellationToken);
            platform.Wait(100, cancellationToken);
            DragRight(platform, cancellationToken);
            platform.Wait(200, cancellationToken);
            platform.ClickGame1080P(1600, 1020, cancellationToken);
            platform.Wait(200, cancellationToken);
            platform.ClickGame1080P(960, 850, cancellationToken);
            return;
        }

        platform.ClickFromBottomRight1080P(225, 60, cancellationToken);
        platform.Wait(100, cancellationToken);
        platform.MoveGame1080P(742, 601, cancellationToken);
        platform.Wait(100, cancellationToken);
        DragRight(platform, cancellationToken);
        platform.Wait(100, cancellationToken);
        platform.ClickGame1080P(1100, 780, cancellationToken);
        platform.Wait(200, cancellationToken);
        platform.ClickFromBottomRight1080P(225, 60, cancellationToken);
        platform.Wait(200, cancellationToken);
    }

    private static void DragRight(
        IQuickBuyRuntimePlatform platform,
        CancellationToken cancellationToken)
    {
        platform.LeftButtonDown(cancellationToken);
        try
        {
            platform.Wait(50, cancellationToken);
            platform.MoveMouseBy(1000, 0, cancellationToken);
            platform.Wait(200, cancellationToken);
        }
        finally
        {
            platform.LeftButtonUp(CancellationToken.None);
        }
    }
}
