using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Recognition;
using BetterGenshinImpact.GameTask.Model.Area;
using Newtonsoft.Json.Linq;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>Forwards observable overlay state to Swift; macOS may choose not to render it.</summary>
public sealed class MacOverlayDrawPlatform(
    PlatformCallbackChannel callbacks, string sessionToken, CancellationToken cancellationToken)
    : IOverlayDrawPlatform
{
    public void SetRectangles(string name, Region source, IReadOnlyList<Rect> rectangles)
    {
        var mapped = rectangles.Select(rect => source.ConvertPositionToGameCaptureRegion(
            rect.X, rect.Y, rect.Width, rect.Height)).Select(rect => new
            { x = rect.X, y = rect.Y, width = rect.Width, height = rect.Height }).ToArray();
        Emit(name, "setRectangles", mapped);
    }

    public void RemoveRectangles(string name) => Emit(name, "removeRectangles", Array.Empty<object>());
    public void ClearAll() => Emit(string.Empty, "clearAll", Array.Empty<object>());

    public void SetLabels(string name, Region source, IReadOnlyList<OverlayLabel> labels)
    {
        var mapped = labels.Select(label =>
        {
            var rect = source.ConvertPositionToGameCaptureRegion(
                label.Rectangle.X, label.Rectangle.Y,
                label.Rectangle.Width, label.Rectangle.Height);
            return new
            {
                x = rect.X, y = rect.Y, width = rect.Width, height = rect.Height,
                text = label.Text, recognized = label.Recognized,
            };
        }).ToArray();
        Emit(name, "setLabels", mapped);
    }
    public void RemoveLabels(string name) => Emit(name, "removeLabels", Array.Empty<object>());

    private void Emit(string name, string operation, object rectangles)
    {
        var response = callbacks.InvokeAsync("overlay.command", JObject.FromObject(new
        {
            name, operation, rectangles,
        }), sessionToken, cancellationToken).GetAwaiter().GetResult();
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException("overlay.command did not return acknowledged=true.");
    }
}
