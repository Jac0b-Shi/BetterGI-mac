using BetterGenshinImpact.GameTask.Common.Element.Assets;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model.Area;
using Microsoft.Extensions.Logging;
using OpenCvSharp;
using System;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.GameTask.Common.BgiVision;
using static BetterGenshinImpact.GameTask.Common.TaskControl;

namespace BetterGenshinImpact.GameTask.AutoCook;

public class AutoCookTask : ISoloTask
{
    private readonly AutoCookConfig _config;
    private readonly double _assetScale;
    private readonly ILogger<AutoCookTask> _logger;
    private const int UiCheckIntervalMs = 400;
    private const int PeakMinCount = 600; // 最小仙跳墙 700 多
    private const int PeakTolerance = 20;
    private const int PeakStableFrameCount = 3;
    private const int TriggerDropCount = 300; // 正常是 400多
    private static readonly Rect CookColorRect1080P = new(600, 660, 730, 190);
    private static readonly Scalar TargetCookColor = new(255, 192, 64);

    public string Name => "自动烹饪";

#if !BGI_PLATFORM_MAC
    public AutoCookTask() : this(
        TaskContext.Instance().Config.AutoCookConfig,
        TaskContext.Instance().SystemInfo.AssetScale,
        App.GetLogger<AutoCookTask>())
    {
    }
#endif

    public AutoCookTask(AutoCookConfig config, double assetScale, ILogger<AutoCookTask> logger)
    {
        _config = config ?? throw new ArgumentNullException(nameof(config));
        _assetScale = assetScale > 0 ? assetScale : throw new ArgumentOutOfRangeException(nameof(assetScale));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    public async Task Start(CancellationToken ct)
    {
        var checkIntervalMs = Math.Max(1, _config.CheckIntervalMs);
        var stopTaskWhenRecoverButtonDetected = _config.StopTaskWhenRecoverButtonDetected;
        var peakMinCount = (int)(PeakMinCount * _assetScale);
        var triggerDropCount = (int)(TriggerDropCount * _assetScale);
        var cookColorRect = ScaleRect(CookColorRect1080P, _assetScale);
        _logger.LogInformation("自动烹饪任务启动");
        var lastUiCheckTime = DateTime.MinValue;
        var inCookUi = false;
        int? peakColorCount = null;
        int? peakCandidate = null;
        var peakCandidateStableFrames = 0;

        while (!ct.IsCancellationRequested)
        {
            using var captureRegion = CaptureToRectArea();
            var now = DateTime.UtcNow;
            if (!inCookUi || (now - lastUiCheckTime).TotalMilliseconds >= UiCheckIntervalMs)
            {
                var currentInCookUi = IsInCookUi(captureRegion);
                if (currentInCookUi != inCookUi)
                {
                    ResetPeakState(ref peakColorCount, ref peakCandidate, ref peakCandidateStableFrames);
                }

                inCookUi = currentInCookUi;
                lastUiCheckTime = now;
                if (!inCookUi)
                {
                    ResetPeakState(ref peakColorCount, ref peakCandidate, ref peakCandidateStableFrames);
                }
                else
                {
                    if (stopTaskWhenRecoverButtonDetected)
                    {
                        var e = captureRegion.Find(ElementRecognition.Get("BtnWhiteRecover", captureRegion));
                        if (e.IsExist())
                        {
                            _logger.LogInformation("自动烹饪：{Text}", "检测到自动烹饪按钮，结束任务");
                            return;
                        }
                    }

                    if (Bv.ClickWhiteConfirmButton(captureRegion))
                    {
                        ResetPeakState(ref peakColorCount, ref peakCandidate, ref peakCandidateStableFrames);
                        _logger.LogInformation("自动烹饪：{Text}", "自动点击确认");
                    }
                }
            }

            if (inCookUi)
            {
                var currentColorCount = CountTargetColor(captureRegion, cookColorRect);
                if (peakColorCount.HasValue)
                {
                    if (currentColorCount <= peakColorCount.Value - triggerDropCount)
                    {
                        TaskControlPlatform.Current.PressKey(0x20);
                        _logger.LogInformation("自动烹饪：{Text}", $"烹饪条像素数量较峰值下降超过{triggerDropCount}，按下空格。峰值:{peakColorCount.Value} 当前:{currentColorCount}");
                        ResetPeakState(ref peakColorCount, ref peakCandidate, ref peakCandidateStableFrames);
                    }
                }
                else if (TryBuildPeak(currentColorCount, peakMinCount, ref peakCandidate, ref peakCandidateStableFrames, out var builtPeak))
                {
                    peakColorCount = builtPeak;
                    _logger.LogInformation("自动烹饪：{Text}", $"识别到完美烹饪条峰值像素数:{builtPeak}");
                }
            }

            await Delay(checkIntervalMs, ct);
        }
    }

    private static void ResetPeakState(ref int? peakColorCount, ref int? peakCandidate, ref int peakCandidateStableFrames)
    {
        peakColorCount = null;
        peakCandidate = null;
        peakCandidateStableFrames = 0;
    }

    private static bool TryBuildPeak(int currentColorCount, int peakMinCount, ref int? peakCandidate, ref int peakCandidateStableFrames, out int builtPeak)
    {
        builtPeak = 0;
        if (currentColorCount <= peakMinCount)
        {
            peakCandidate = null;
            peakCandidateStableFrames = 0;
            return false;
        }

        if (!peakCandidate.HasValue)
        {
            peakCandidate = currentColorCount;
            peakCandidateStableFrames = 1;
            return false;
        }

        if (Math.Abs(currentColorCount - peakCandidate.Value) <= PeakTolerance)
        {
            peakCandidate = Math.Max(peakCandidate.Value, currentColorCount);
            peakCandidateStableFrames++;
            if (peakCandidateStableFrames >= PeakStableFrameCount && peakCandidate.Value > peakMinCount)
            {
                builtPeak = peakCandidate.Value;
                peakCandidate = null;
                peakCandidateStableFrames = 0;
                return true;
            }

            return false;
        }

        peakCandidate = currentColorCount;
        peakCandidateStableFrames = 1;
        return false;
    }

    private static Rect ScaleRect(Rect rect, double scale)
    {
        return new Rect(
            (int)(rect.X * scale),
            (int)(rect.Y * scale),
            (int)(rect.Width * scale),
            (int)(rect.Height * scale));
    }

    private bool IsInCookUi(ImageRegion captureRegion)
    {
        using var cookIcon = captureRegion.Find(ElementRecognition.Get("UiLeftTopCookIcon", captureRegion));
        return cookIcon.IsExist();
    }

    private int CountTargetColor(ImageRegion captureRegion, Rect cookColorRect)
    {
        using var crop = captureRegion.DeriveCrop(cookColorRect);
        using var rgb = new Mat();
        using var mask = new Mat();
        Cv2.CvtColor(crop.SrcMat, rgb, ColorConversionCodes.BGR2RGB);
        Cv2.InRange(rgb, TargetCookColor, TargetCookColor, mask);
        return Cv2.CountNonZero(mask);
    }
}
