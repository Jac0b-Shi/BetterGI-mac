using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask.AutoPathing;
using Newtonsoft.Json.Linq;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacNavigationPlatform(
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken cancellationToken) : INavigationPlatform
{
    public void PublishCurrentPosition(Point2f position)
    {
        var response = callbacks.InvokeAsync(
                "pathing.position",
                JObject.FromObject(new { x = position.X, y = position.Y }),
                sessionToken,
                cancellationToken)
            .GetAwaiter().GetResult();
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException("pathing.position did not return acknowledged=true.");
    }
}
