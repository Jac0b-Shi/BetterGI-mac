using BetterGenshinImpact.Core.Runtime.Windows;
using BetterGenshinImpact.Platform.Abstractions;

// Compile-time verification that adapter types are resolvable.
// This file is never executed — it only exists to force the compiler
// to type-check Win32InputBackend, Win32InputHelpers, IInputBackend,
// Fischless API calls, and Vanara type conversions.

public static class AdapterBuildVerification
{
    // IInputBackend instantiation check
    static readonly IInputBackend _backend = new Win32InputBackend();

    // Win32InputHelpers pure-function resolution check
    static readonly int _vkCode = Win32InputHelpers.MapBgiKeyToVk(BgiKey.F);

    // Win32InputHelpers coordinate conversion check
    static readonly (int nx, int ny) _norm =
        Win32InputHelpers.ScreenToNormalized(0, 0, 0, 0, 1920, 1080);

    // Fischless + Vanara type resolution (used in Win32InputBackend methods)
    static void VerifyBackendMethods()
    {
        _backend.KeyPress(BgiKey.F);
        _backend.Scroll(2);
        _backend.MoveMouseTo(960, 540);
        _backend.MoveMouseBy(10, 10);
        _backend.LeftButtonDown();
        _backend.LeftButtonUp();
        _backend.LeftClick(960, 540);
        _backend.KeyDown(BgiKey.LeftShift);
        _backend.KeyUp(BgiKey.LeftShift);
    }
}
