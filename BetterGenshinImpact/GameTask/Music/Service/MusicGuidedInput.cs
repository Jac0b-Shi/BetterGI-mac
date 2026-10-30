using System;

namespace BetterGenshinImpact.GameTask.Music.Service;

public interface IMusicGuidedInput : IDisposable
{
    event Action<int>? KeyPressed;
    event Action<int>? KeyReleased;
    bool Start();
    void Stop();
}

#if !BGI_PLATFORM_MAC
internal sealed class WindowsMusicGuidedInput : IMusicGuidedInput
{
    private readonly MusicPlayerInputHook _hook = new();
    public event Action<int>? KeyPressed;
    public event Action<int>? KeyReleased;
    public WindowsMusicGuidedInput()
    {
        _hook.KeyPressed += key => KeyPressed?.Invoke((int)key);
        _hook.KeyReleased += key => KeyReleased?.Invoke((int)key);
    }
    public bool Start() => _hook.Start();
    public void Stop() => _hook.Stop();
    public void Dispose() => _hook.Dispose();
}
#endif
