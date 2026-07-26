using BetterGenshinImpact.Core.Simulator.Extensions;
using Microsoft.Extensions.Logging;
using OpenCvSharp;
using System;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.GameTask.Common;
using static BetterGenshinImpact.GameTask.Common.TaskControl;

namespace BetterGenshinImpact.GameTask.AutoMusicGame;

public class AutoMusicGameTask : ISoloTask
{
    private readonly IAutoMusicGameRuntimePlatform runtimePlatform;

    public AutoMusicGameTask(
        AutoMusicGameParam taskParam,
        IAutoMusicGameRuntimePlatform runtimePlatform)
    {
        ArgumentNullException.ThrowIfNull(taskParam);
        this.runtimePlatform = runtimePlatform;
    }

    public string Name => "自动音游";


    private static readonly (int Key, int X)[] KeyLanes =
    [
        (0x41, 417),
        (0x53, 628),
        (0x44, 844),
        (0x4A, 1061),
        (0x4B, 1277),
        (0x4C, 1493)
    ];

    private readonly int _keyY = 921;

    public async Task Start(CancellationToken ct)
    {
        Init(runtimePlatform);
        await StartWithOutInit(ct);
    }

    public async Task StartWithOutInit(CancellationToken ct)
    {
        try
        {
            Logger.LogInformation("开始自动演奏");
            var assetScale = runtimePlatform.AssetScale;
            var points = new Point[KeyLanes.Length];
            var blueChannels = new byte[KeyLanes.Length];
            var pressed = new bool[KeyLanes.Length];
            for (var index = 0; index < KeyLanes.Length; index++)
            {
                points[index] = new Point(
                    (int)(KeyLanes[index].X * assetScale),
                    (int)(_keyY * assetScale));
            }

            while (!ct.IsCancellationRequested)
            {
                await Task.Delay(5, ct);
                runtimePlatform.ReadBlueChannels(points, blueChannels);
                for (var index = 0; index < KeyLanes.Length; index++)
                {
                    var shouldPress = blueChannels[index] < 220;
                    if (shouldPress == pressed[index])
                    {
                        continue;
                    }

                    if (shouldPress)
                        KeyDown(KeyLanes[index].Key);
                    else
                        KeyUp(KeyLanes[index].Key);
                    pressed[index] = shouldPress;
                }
            }
        }
        finally
        {
            TaskControlPlatform.Current.ReleasePressedInputs();
            Logger.LogInformation("结束自动演奏");
        }
    }

    private static void KeyUp(int key)
    {
        TaskControlPlatform.Current.KeyUp(key);
    }

    private static void KeyDown(int key)
    {
        TaskControlPlatform.Current.KeyDown(key);
    }

    public static void Init(IAutoMusicGameRuntimePlatform runtimePlatform)
    {
        LogScreenResolution(runtimePlatform);
    }

    public static void LogScreenResolution(IAutoMusicGameRuntimePlatform runtimePlatform)
    {
        runtimePlatform.ValidateResolution();

        Logger.LogInformation("{Name}：回到游戏主界面时记得关闭自动音游任务！", "千音雅集");
        Logger.LogWarning("{Name}：默认的样式“轻漾涟漪”是{No}的！需要手动完成几首曲目获得{Money}千音币后兑换并使用胡桃样式“{Hutao}”！", "千音雅集", "不可用", 600, "疏影引蝶映梅红");
    }
}
