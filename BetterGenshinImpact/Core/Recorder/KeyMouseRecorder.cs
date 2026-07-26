using BetterGenshinImpact.Core.Recorder.Model;
using BetterGenshinImpact.Core.Monitor;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Common.Map;
using Gma.System.MouseKeyHook;
using System;
using System.Collections.Generic;
using System.Windows.Forms;

namespace BetterGenshinImpact.Core.Recorder;

public class KeyMouseRecorder
{
    public List<MacroEvent> MacroEvents { get; } = [];

    public DateTime StartTime { get; set; } = DateTime.UtcNow;

    public DateTime LastOrientationDetection { get; set; } = DateTime.UtcNow;

    public double MergedEventTimeMax { get; set; } = 20.0;

    public static readonly System.Text.Json.JsonSerializerOptions JsonOptions =
        KeyMouseScriptBuilder.JsonOptions;

    public string ToJsonMacro()
    {
        var rect = TaskContext.Instance().SystemInfo.CaptureAreaRect;
        return KeyMouseScriptBuilder.ToJson(
            MacroEvents,
            new KeyMouseScriptInfo
            {
                X = rect.X,
                Y = rect.Y,
                Width = rect.Width,
                Height = rect.Height,
                RecordDpi = TaskContext.Instance().DpiScale
            },
            MergedEventTimeMax);
    }

    public void KeyDown(KeyEventArgs e, DateTime time)
    {
        MacroEvents.Add(new MacroEvent
        {
            Type = MacroEventType.KeyDown,
            KeyCode = e.KeyValue,
            Time = (time - StartTime).TotalMilliseconds
        });
    }

    public void KeyUp(KeyEventArgs e, DateTime time)
    {
        MacroEvents.Add(new MacroEvent
        {
            Type = MacroEventType.KeyUp,
            KeyCode = e.KeyValue,
            Time = (time - StartTime).TotalMilliseconds
        });
    }

    public void MouseDown(MouseEventExtArgs e, DateTime time)
    {
        MacroEvents.Add(new MacroEvent
        {
            Type = MacroEventType.MouseDown,
            MouseX = e.X,
            MouseY = e.Y,
            MouseButton = e.Button.ToString(),
            Time = (time - StartTime).TotalMilliseconds
        });
    }

    public void MouseUp(MouseEventExtArgs e, DateTime time)
    {
        MacroEvents.Add(new MacroEvent
        {
            Type = MacroEventType.MouseUp,
            MouseX = e.X,
            MouseY = e.Y,
            MouseButton = e.Button.ToString(),
            Time = (time - StartTime).TotalMilliseconds
        });
    }

    public void MouseMoveTo(MouseEventExtArgs e, DateTime time)
    {
        MacroEvents.Add(new MacroEvent
        {
            Type = MacroEventType.MouseMoveTo,
            MouseX = e.X,
            MouseY = e.Y,
            Time = (time - StartTime).TotalMilliseconds
        });
    }
    
    public void MouseWheel(MouseEventExtArgs e, DateTime time)
    {
        MacroEvents.Add(new MacroEvent
        {
            Type = MacroEventType.MouseWheel,
            MouseY = e.Delta, // 120 的倍率
            Time = (time - StartTime).TotalMilliseconds
        });
    }

    public void MouseMoveBy(RelativeMouseMoveEventArgs e)
    {
        
        int? cao = null;
        if (TaskContext.Instance().Config.RecordConfig.IsRecordCameraOrientation)
        {
            var now = DateTime.UtcNow;
            if ((now - LastOrientationDetection).TotalMilliseconds > 100.0)
            {
                LastOrientationDetection = now;
                cao = (int)Math.Round(CameraOrientation.Compute(TaskControl.CaptureToRectArea().SrcMat));
            }
        }
        
        MacroEvents.Add(new MacroEvent
        {
            Type = MacroEventType.MouseMoveBy,
            MouseX = e.DeltaX,
            MouseY = e.DeltaY,
            Time = (e.Timestamp - StartTime).TotalMilliseconds,
            CameraOrientation = cao,
        });
    }
}
