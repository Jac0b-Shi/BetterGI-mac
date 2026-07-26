using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.AutoGeniusInvokation.Exception;
using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.Extensions.Logging;
using System;
using System.Threading;
using System.Threading.Tasks;
#if BGI_FULL_WINDOWS
using Fischless.GameCapture;
using OpenCvSharp;
#endif

namespace BetterGenshinImpact.GameTask.Common;

public class TaskControl
{
    public static ILogger Logger => TaskControlPlatform.Current.Logger;
    public static readonly SemaphoreSlim TaskSemaphore = new(1, 1);

    public static void CheckAndSleep(int millisecondsTimeout)
    {
        TrySuspend();
        TaskControlPlatform.Current.EnsureGameActive();
        Thread.Sleep(millisecondsTimeout);
    }

    public static void Sleep(int millisecondsTimeout)
    {
        NewRetry.Do(() =>
        {
            TrySuspend();
            TaskControlPlatform.Current.EnsureGameActive();
        }, TimeSpan.FromSeconds(1), 100);
        Thread.Sleep(millisecondsTimeout);
    }

    public static void TrySuspend()
    {
        var first = true;
        var wasSuspended = RunnerContext.Instance.IsSuspend;
        while (RunnerContext.Instance.IsSuspend)
        {
            if (first)
            {
                RunnerContext.Instance.StopAutoPick();
                Thread.Sleep(300);
                TaskControlPlatform.Current.ReleasePressedInputs();
                Logger.LogWarning("快捷键触发暂停，等待解除");
                foreach (var item in RunnerContext.Instance.SuspendableDictionary)
                    item.Value.Suspend();
                first = false;
            }
            Thread.Sleep(1000);
        }

        if (wasSuspended)
        {
            Logger.LogWarning("暂停已经解除");
            RunnerContext.Instance.ResumeAutoPick();
            foreach (var item in RunnerContext.Instance.SuspendableDictionary)
                item.Value.Resume();
        }
    }

    public static void Sleep(int millisecondsTimeout, CancellationToken ct)
    {
        ThrowIfCancelled(ct);
        if (millisecondsTimeout <= 0) return;
        NewRetry.Do(() =>
        {
            ThrowIfCancelled(ct);
            TrySuspend();
            TaskControlPlatform.Current.EnsureGameActive();
        }, TimeSpan.FromSeconds(1), 100);
        Thread.Sleep(millisecondsTimeout);
        ThrowIfCancelled(ct);
    }

    public static async Task Delay(int millisecondsTimeout, CancellationToken ct)
    {
        ThrowIfCancelled(ct);
        if (millisecondsTimeout <= 0) return;
        NewRetry.Do(() =>
        {
            ThrowIfCancelled(ct);
            TrySuspend();
            TaskControlPlatform.Current.EnsureGameActive();
        }, TimeSpan.FromSeconds(1), 100);
        await Task.Delay(millisecondsTimeout, ct);
        ThrowIfCancelled(ct);
    }

    public static async Task SimulateHoldActionAsync(GIActions action, int holdMs, CancellationToken ct)
    {
        try
        {
            TaskControlPlatform.Current.SimulateAction(action, KeyType.KeyDown);
            await Delay(holdMs, ct);
        }
        finally
        {
            TaskControlPlatform.Current.SimulateAction(action, KeyType.KeyUp);
        }
    }

    public static void SimulateAction(GIActions action, KeyType keyType = KeyType.KeyPress) =>
        TaskControlPlatform.Current.SimulateAction(action, keyType);

    public static void ReleaseAllKey() => TaskControlPlatform.Current.ReleasePressedInputs();

    public static bool IsActionKeyDown(GIActions action) =>
        TaskControlPlatform.Current.IsActionKeyDown(action);

    public static void MoveMouseBy(int x, int y) => TaskControlPlatform.Current.MoveMouseBy(x, y);

    public static void RightButtonUp() => TaskControlPlatform.Current.RightButtonUp();

    public static void MiddleButtonClick() => TaskControlPlatform.Current.MiddleButtonClick();
    public static void MiddleButtonDown() => TaskControlPlatform.Current.MiddleButtonDown();
    public static void MiddleButtonUp() => TaskControlPlatform.Current.MiddleButtonUp();
    public static void LeftButtonDown() => TaskControlPlatform.Current.LeftButtonDown();
    public static void LeftButtonUp() => TaskControlPlatform.Current.LeftButtonUp();
    public static void LeftButtonClick() => TaskControlPlatform.Current.LeftButtonClick();

    public static void PressEscape() => TaskControlPlatform.Current.PressEscape();

    public static async Task SimulateHoldElementalSkillAsync(
        int holdMs, CancellationToken ct, bool releaseLeftMouseBefore = true,
        int releaseLeftMouseDelayMs = 10, int postKeyUpDelayMs = 50)
    {
        if (releaseLeftMouseBefore)
        {
            TaskControlPlatform.Current.LeftButtonUp();
            await Delay(releaseLeftMouseDelayMs, ct);
        }
        await SimulateHoldActionAsync(GIActions.ElementalSkill, holdMs, ct);
        await Delay(postKeyUpDelayMs, ct);
    }

    public static async Task SimulateMouseLeftClickLoopAsync(
        int repeatCount, CancellationToken ct, int preUpDelayMs = 10,
        int downHoldMs = 35, int postUpDelayMs = 50)
    {
        try
        {
            for (var i = 0; i < repeatCount; i++)
            {
                TaskControlPlatform.Current.LeftButtonUp();
                await Delay(preUpDelayMs, ct);
                TaskControlPlatform.Current.LeftButtonDown();
                try { await Delay(downHoldMs, ct); }
                finally { TaskControlPlatform.Current.LeftButtonUp(); }
                await Delay(postUpDelayMs, ct);
            }
        }
        finally
        {
            TaskControlPlatform.Current.LeftButtonUp();
        }
    }

#if BGI_FULL_WINDOWS
    public static Mat CaptureGameImage(IGameCapture? gameCapture)
    {
        var captureFrame = gameCapture?.Capture();
        var image = captureFrame?.Frame;
        if (image == null)
        {
            captureFrame?.Dispose();
            Logger.LogWarning("截图失败!");
            // 重试3次
            for (var i = 0; i < 3; i++)
            {
                captureFrame = gameCapture?.Capture();
                image = captureFrame?.Frame;
                if (image != null)
                {
                    return image;
                }

                captureFrame?.Dispose();
                Sleep(30);
            }

            throw new Exception("尝试多次后,截图失败!");
        }
        else
        {
            return image;
        }
    }

    public static Mat? CaptureGameImageNoRetry(IGameCapture? gameCapture)
    {
        return gameCapture?.Capture()?.Frame;
    }
#endif

    public static ImageRegion CaptureToRectArea(bool forceNew = false) =>
        TaskControlPlatform.Current.CaptureToRectArea(forceNew);

    private static void ThrowIfCancelled(CancellationToken ct)
    {
        if (ct.IsCancellationRequested)
            throw new NormalEndException("取消自动任务");
    }
}
