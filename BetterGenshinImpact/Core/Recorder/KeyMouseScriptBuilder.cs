using BetterGenshinImpact.Core.Recorder.Model;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace BetterGenshinImpact.Core.Recorder;

public static class KeyMouseScriptBuilder
{
    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        NumberHandling = JsonNumberHandling.AllowNamedFloatingPointLiterals,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        AllowTrailingCommas = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public static KeyMouseScript Build(
        IEnumerable<MacroEvent> events,
        KeyMouseScriptInfo info,
        double mergedEventTimeMax = 20.0)
    {
        var orderedEvents = events
            .Where(macroEvent => macroEvent.Time >= 0)
            .OrderBy(macroEvent => macroEvent.Time)
            .ToList();
        var mergedEvents = new List<MacroEvent>();
        MacroEvent? currentMerge = null;

        foreach (var macroEvent in orderedEvents)
        {
            if (currentMerge == null)
            {
                currentMerge = macroEvent;
                continue;
            }

            if (currentMerge.Type != macroEvent.Type)
            {
                mergedEvents.Add(currentMerge);
                currentMerge = macroEvent;
                continue;
            }

            switch (macroEvent.Type)
            {
                case MacroEventType.MouseMoveTo:
                    if (macroEvent.Time - currentMerge.Time > mergedEventTimeMax)
                    {
                        mergedEvents.Add(currentMerge);
                        currentMerge = macroEvent;
                        break;
                    }
                    currentMerge.MouseX = macroEvent.MouseX;
                    currentMerge.MouseY = macroEvent.MouseY;
                    break;
                case MacroEventType.MouseMoveBy:
                    if (macroEvent.Time - currentMerge.Time > mergedEventTimeMax)
                    {
                        mergedEvents.Add(currentMerge);
                        currentMerge = macroEvent;
                        break;
                    }
                    currentMerge.MouseX += macroEvent.MouseX;
                    currentMerge.MouseY += macroEvent.MouseY;
                    if (macroEvent.CameraOrientation != null)
                        currentMerge.CameraOrientation = macroEvent.CameraOrientation;
                    break;
                default:
                    mergedEvents.Add(currentMerge);
                    mergedEvents.Add(macroEvent);
                    currentMerge = null;
                    break;
            }
        }

        if (currentMerge != null)
            mergedEvents.Add(currentMerge);

        return new KeyMouseScript
        {
            MacroEvents = mergedEvents,
            Info = info
        };
    }

    public static string ToJson(
        IEnumerable<MacroEvent> events,
        KeyMouseScriptInfo info,
        double mergedEventTimeMax = 20.0) =>
        JsonSerializer.Serialize(Build(events, info, mergedEventTimeMax), JsonOptions);

    public static string ToJson(KeyMouseScript script) =>
        JsonSerializer.Serialize(script, JsonOptions);
}
