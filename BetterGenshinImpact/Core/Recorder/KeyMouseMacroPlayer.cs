using BetterGenshinImpact.Core.Recorder.Model;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.Core.Recorder;

public class KeyMouseMacroPlayer
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        NumberHandling = JsonNumberHandling.AllowNamedFloatingPointLiterals,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        AllowTrailingCommas = true
    };

    public static async Task PlayMacro(string macro, CancellationToken ct, bool withDelay = true)
    {
        var platform = KeyMouseMacroPlatform.Current;
        if (!platform.IsInitialized)
            throw new InvalidOperationException("请先启动截图器再执行键鼠脚本。");

        var script = JsonSerializer.Deserialize<KeyMouseScript>(macro, JsonOptions)
            ?? throw new JsonException("Failed to deserialize macro");
        script.Adapt(platform.CaptureArea, platform.DpiScale);
        platform.ActivateGameWindow();

        if (withDelay)
        {
            for (var i = 3; i >= 1; i--)
            {
                platform.Logger.LogInformation("{Sec}秒后进行重放...", i);
                await Task.Delay(1000, ct);
            }
            platform.Logger.LogInformation("开始重放");
        }

        await PlayMacro(script.MacroEvents, ct);
    }

    public static async Task PlayMacro(List<MacroEvent> macroEvents, CancellationToken ct)
    {
        var platform = KeyMouseMacroPlatform.Current;
        WorkingArea = platform.WorkingArea;
        if (WorkingArea.Width <= 0 || WorkingArea.Height <= 0)
            throw new InvalidOperationException("Macro working area must have positive dimensions.");

        var startTime = Environment.TickCount64;
        foreach (var e in macroEvents)
        {
            ct.ThrowIfCancellationRequested();
            var timeToWait = e.Time - (Environment.TickCount64 - startTime);
            if (timeToWait < 0)
                platform.Logger.LogDebug("无法原速重放事件{Event}，落后{TimeToWait}ms", e.Type, (-timeToWait).ToString("F0"));
            else
                await Task.Delay((int)timeToWait, ct);

            switch (e.Type)
            {
                case MacroEventType.KeyDown:
                    platform.KeyDown(e.KeyCode ?? throw new InvalidDataException("KeyDown event has no keyCode."));
                    break;
                case MacroEventType.KeyUp:
                    platform.KeyUp(e.KeyCode ?? throw new InvalidDataException("KeyUp event has no keyCode."));
                    break;
                case MacroEventType.MouseDown:
                    platform.MoveMouseTo(ToVirtualDesktopX(e.MouseX), ToVirtualDesktopY(e.MouseY));
                    platform.MouseDown(NormalizeButton(e.MouseButton));
                    break;
                case MacroEventType.MouseUp:
                    platform.MoveMouseTo(ToVirtualDesktopX(e.MouseX), ToVirtualDesktopY(e.MouseY));
                    platform.MouseUp(NormalizeButton(e.MouseButton));
                    break;
                case MacroEventType.MouseMoveTo:
                    platform.MoveMouseTo(ToVirtualDesktopX(e.MouseX), ToVirtualDesktopY(e.MouseY));
                    break;
                case MacroEventType.MouseWheel:
                    var clicks = (int)(e.MouseY / 120.0);
                    if (clicks != 0) platform.VerticalScroll(clicks);
                    break;
                case MacroEventType.MouseMoveBy:
                    if (e.CameraOrientation != null)
                    {
                        var orientation = platform.GetCameraOrientation();
                        var diff = ((int)Math.Round(orientation) - e.CameraOrientation.Value + 180) % 360 - 180;
                        diff += diff < -180 ? 360 : 0;
                        if (diff is < 8 and > -8 && diff != 0)
                        {
                            platform.Logger.LogWarning("视角重放偏差{Diff}°，尝试修正", diff);
                            e.MouseX -= diff;
                        }
                    }
                    platform.MoveMouseBy(e.MouseX, e.MouseY);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(e.Type), e.Type, "Unknown macro event type.");
            }
        }
    }

    public static Size WorkingArea;
    public static double ToVirtualDesktopX(int x) => x * 65535d / WorkingArea.Width;
    public static double ToVirtualDesktopY(int y) => y * 65535d / WorkingArea.Height;

    private static string NormalizeButton(string? button) => button?.ToLowerInvariant() switch
    {
        "left" => "left",
        "right" => "right",
        "middle" => "middle",
        "xbutton1" => "side1",
        "xbutton2" => "side2",
        "none" => throw new NotSupportedException(
            $"Mouse button '{button}' is not supported by BetterGI macro playback."),
        _ => throw new InvalidDataException($"Invalid mouse button '{button}'.")
    };
}
