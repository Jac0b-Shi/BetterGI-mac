using OpenCvSharp;
using System;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace BetterGenshinImpact.Core.Config;

/// <summary>
/// Shared configuration JSON contract. The WPF service and the macOS Core must
/// deserialize script settings with the exact same naming and OpenCV rules.
/// </summary>
public static class ConfigJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        NumberHandling = JsonNumberHandling.AllowNamedFloatingPointLiterals,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new OpenCvPointJsonConverter(), new OpenCvRectJsonConverter() },
        WriteIndented = true,
        AllowTrailingCommas = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
    };
}

public sealed class OpenCvRectJsonConverter : JsonConverter<Rect>
{
    public override unsafe Rect Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var helper = JsonSerializer.Deserialize<RectHelper>(ref reader, options);
        return *(Rect*)&helper;
    }

    public override unsafe void Write(Utf8JsonWriter writer, Rect value, JsonSerializerOptions options)
    {
        var helper = *(RectHelper*)&value;
        JsonSerializer.Serialize(writer, helper, options);
    }

    private struct RectHelper { public int X { get; set; } public int Y { get; set; } public int Width { get; set; } public int Height { get; set; } }
}

public sealed class OpenCvPointJsonConverter : JsonConverter<Point>
{
    public override unsafe Point Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var helper = JsonSerializer.Deserialize<PointHelper>(ref reader, options);
        return *(Point*)&helper;
    }

    public override unsafe void Write(Utf8JsonWriter writer, Point value, JsonSerializerOptions options)
    {
        var helper = *(PointHelper*)&value;
        JsonSerializer.Serialize(writer, helper, options);
    }

    private struct PointHelper { public int X { get; set; } public int Y { get; set; } }
}
