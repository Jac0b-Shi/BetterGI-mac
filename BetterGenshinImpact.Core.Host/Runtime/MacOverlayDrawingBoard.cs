using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Mask;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using System.Threading.Channels;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>业务侧立即写入完整快照，单一异步发布器合并通知；删除不会因丢弃中间帧而遗漏。</summary>
public sealed class MacOverlayDrawingBoard : IMaskWindowDrawingBoard, IAsyncDisposable
{
    private readonly MaskWindowDrawingBoard _board = new();
    private readonly Channel<bool> _changes = Channel.CreateBounded<bool>(new BoundedChannelOptions(1)
        { FullMode = BoundedChannelFullMode.DropOldest, SingleReader = true });
    private readonly CancellationTokenSource _lifetime;
    private readonly Task _publisher;

    public MacOverlayDrawingBoard(PlatformCallbackChannel callbacks, string sessionToken,
        CancellationToken cancellationToken, ILogger logger)
    {
        _lifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _board.Changed += Changed;
        _publisher = PublishAsync(callbacks, sessionToken, logger, _lifetime.Token);
    }
    public void Set(MaskWindowDrawingGroup group, IReadOnlyList<MaskWindowDrawingShape>? shapes) => _board.Set(group, shapes);
    public void Clear(MaskWindowDrawingGroup group) => _board.Clear(group);
    public void ClearAll() => _board.ClearAll();
    private void Changed() => _changes.Writer.TryWrite(true);
    private async Task PublishAsync(PlatformCallbackChannel callbacks, string token, ILogger logger, CancellationToken ct)
    {
        try
        {
            await foreach (var _ in _changes.Reader.ReadAllAsync(ct))
            {
                while (!ct.IsCancellationRequested)
                {
                    try
                    {
                        var snapshot = _board.Current;
                        var payload = JObject.FromObject(new {
                            name = "MaskWindowDrawing", operation = "setDrawingSnapshot", version = snapshot.Version,
                            groups = snapshot.Entries.Select(entry => new {
                                name = entry.Group.Name, kind = entry.Group.Kind.ToString(),
                                shapes = entry.Shapes.Select(Encode).ToArray()
                            }).ToArray()
                        });
                        var response = await callbacks.InvokeAsync("overlay.command", payload, token, ct);
                        if (response?.Value<bool?>("acknowledged") != true)
                            throw new InvalidDataException("Drawing snapshot was not acknowledged.");
                        break;
                    }
                    catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
                    catch (Exception e)
                    {
                        logger.LogWarning(e, "macOS drawing snapshot publish failed; retrying latest snapshot");
                        await Task.Delay(250, ct);
                    }
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { }
    }
    private static object Encode(MaskWindowDrawingShape shape) => shape switch
    {
        MaskWindowDrawingRect r => new { type = "rect", x = r.Bounds.X, y = r.Bounds.Y,
            width = r.Bounds.Width, height = r.Bounds.Height, color = Color(r.Stroke?.Color), thickness = r.Stroke?.Thickness },
        MaskWindowDrawingLine l => new { type = "line", x = l.From.X, y = l.From.Y, x2 = l.To.X, y2 = l.To.Y,
            color = Color(l.Stroke?.Color), thickness = l.Stroke?.Thickness },
        MaskWindowDrawingText t => new { type = "text", text = t.Text, x = t.Origin.X, y = t.Origin.Y,
            color = Color(t.Style?.Foreground), background = Color(t.Style?.Background), fontSize = t.Style?.FontSize, numeric = t.Style?.Numeric ?? false },
        _ => throw new NotSupportedException($"Unsupported drawing shape: {shape.GetType().Name}")
    };
    private static string? Color(System.Drawing.Color? color) => color is { } c ? $"#{c.A:X2}{c.R:X2}{c.G:X2}{c.B:X2}" : null;
    public async ValueTask DisposeAsync()
    {
        _board.Changed -= Changed;
        _changes.Writer.TryComplete();
        await _lifetime.CancelAsync();
        await _publisher;
        _lifetime.Dispose();
    }
}
