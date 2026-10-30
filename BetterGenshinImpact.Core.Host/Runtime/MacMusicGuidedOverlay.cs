using BetterGenshinImpact.Core.Mask;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.Music.Service;
using System.Drawing;

namespace BetterGenshinImpact.Core.Host.Runtime;

/// <summary>Draws upstream key positions through the existing macOS drawing board.</summary>
internal sealed class MacMusicGuidedOverlay : IMusicGuidedOverlay
{
    private readonly MaskWindowDrawingGroup _group = new("MusicGuided", MaskWindowDrawingKind.Feature);
    private readonly IMaskWindowDrawingBoard _board;
    private readonly object _sync = new();
    private readonly MusicGuidedKeyLayoutConfig _layout;
    private IReadOnlyList<MusicGuidedPress> _presses = [];
    private IReadOnlyDictionary<char, GuidedKeyPosition> _positions = new Dictionary<char, GuidedKeyPosition>();
    private HashSet<int> _satisfied = [];
    private HashSet<char> _held = [];
    private string _title = string.Empty;
    public MacMusicGuidedOverlay(IMaskWindowDrawingBoard board, (double Width, double Height) size, MusicGuidedKeyLayoutConfig layout)
    { _board = board; CanvasSize = size; _layout = layout; }
    public bool IsAttached { get; private set; }
    public (double Width, double Height) CanvasSize { get; }
    public event Action? ExitRequested { add { } remove { } }
    public bool Attach(nint gameHandle) { lock (_sync) { IsAttached = gameHandle != 0; return IsAttached; } }
    public void UpdateDetach() { lock (_sync) { IsAttached = false; _board.Clear(_group); } }
    public void UpdateSegment(int index, int total, IReadOnlyList<MusicGuidedPress> presses,
        IReadOnlyDictionary<char, GuidedKeyPosition> positions, string trackName, IReadOnlyList<int> satisfiedPressIndices)
    { lock (_sync) { _presses = presses; _positions = positions; _satisfied = satisfiedPressIndices.ToHashSet(); _title = $"{trackName} · {index + 1}/{total}"; Render(); } }
    public void UpdateProgress(IReadOnlyList<int> satisfiedPressIndices, IReadOnlyList<char> heldKeys)
    { lock (_sync) { _satisfied = satisfiedPressIndices.ToHashSet(); _held = heldKeys.ToHashSet(); Render(); } }
    public void UpdateError(string wrongKeys) => Render($"按错：{wrongKeys}，重弹当前段");
    public void UpdateOrderHint(string expectedKeys) => Render($"请先弹：{expectedKeys}");
    public void UpdateCompleted(string trackName) => UpdateDetach();
    public void UpdateDetection(string text) { }
    public void UpdateStopped(string reason) => UpdateDetach();
    private void Render(string? hint = null)
    {
        lock (_sync)
        {
        if (!IsAttached) return;
        var shapes = new List<MaskWindowDrawingShape>();
        shapes.Add(new MaskWindowDrawingText(hint ?? _title, new MaskPoint(25, 60), new MaskWindowDrawingTextStyle(Color.White, 24)));
        for (var i = 0; i < _presses.Count; i++)
        {
            if (_satisfied.Contains(i)) continue;
            foreach (var key in _presses[i].Keys)
            {
                if (!_positions.TryGetValue(key, out var p)) continue;
                var radius = p.Size / 2 * (1 + .16 * i);
                var stroke = new MaskWindowDrawingStroke(_held.Contains(key) ? Color.Lime : Color.Gold, Math.Max(1, _layout.RingThickness * Math.Min(CanvasSize.Width / 1920, CanvasSize.Height / 1080)));
                // Closed polyline rings use the same portable drawing primitives as the HUD.
                for (var segment = 0; segment < 40; segment++)
                {
                    MaskPoint PointAt(int n) => new(p.X + radius * Math.Cos(n * Math.Tau / 40), p.Y + radius * Math.Sin(n * Math.Tau / 40));
                    shapes.Add(new MaskWindowDrawingLine(PointAt(segment), PointAt(segment + 1), stroke));
                }
                shapes.Add(new MaskWindowDrawingText($"{i + 1}:{key}", new MaskPoint(p.X - radius / 2, p.Y - radius - 22), new MaskWindowDrawingTextStyle(Color.Gold, 20)));
            }
        }
        _board.Set(_group, shapes);
        }
    }
}

internal sealed class MacMusicGuidedInput : IMusicGuidedInput
{
    private readonly HashSet<int> _held = [];
    private bool _running;
    public bool HasModifiers { get; private set; }
    public event Action<int>? KeyPressed;
    public event Action<int>? KeyReleased;
    public bool Start() { _running = true; return true; }
    public void Submit(int key, bool down, bool modifiers)
    {
        if (!_running) return;
        HasModifiers = modifiers;
        if (down) { if (_held.Add(key)) KeyPressed?.Invoke(key); }
        else if (_held.Remove(key)) KeyReleased?.Invoke(key);
    }
    public void Stop() { foreach (var key in _held.ToArray()) Submit(key, false, false); _running = false; }
    public void Dispose() => Stop();
}
