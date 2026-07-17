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
    public void SetRectangles(string name, ImageRegion source, IReadOnlyList<Rect> rectangles)
    {
        var mapped = rectangles.Select(rect => source.ConvertPositionToGameCaptureRegion(
            rect.X, rect.Y, rect.Width, rect.Height)).Select(rect => new
            { x = rect.X, y = rect.Y, width = rect.Width, height = rect.Height }).ToArray();
        Emit(name, "setRectangles", mapped);
    }

    public void RemoveRectangles(string name) => Emit(name, "removeRectangles", Array.Empty<object>());
    public void ClearAll() => Emit(string.Empty, "clearAll", Array.Empty<object>());

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
