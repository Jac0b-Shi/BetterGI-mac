#if BGI_PLATFORM_MAC
using InputKey = System.Int32;
#else
using InputKey = Vanara.PInvoke.User32.VK;
#endif

namespace BetterGenshinImpact.Core.Input;

/// <summary>
/// 键盘输入。传入鼠标键 VK（VK_LBUTTON、VK_RBUTTON、VK_MBUTTON、VK_XBUTTON1、VK_XBUTTON2）时按对应鼠标键处理
/// </summary>
public interface IKeyboardInput
{
    IKeyboardInput KeyDown(InputKey key);

    IKeyboardInput KeyUp(InputKey key);

    IKeyboardInput KeyPress(InputKey key);

    IKeyboardInput Sleep(int ms);
}
