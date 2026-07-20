using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.Core.Recognition;
#if !BGI_PLATFORM_MAC
using BetterGenshinImpact.Core.Simulator;
using Fischless.WindowsInput;
#endif
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model.Area;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.BgiVision;

public class BvPage
{
    private readonly CancellationToken _cancellationToken;

#if BGI_PLATFORM_MAC
    public BvKeyboard Keyboard { get; } = new();

    public BvMouse Mouse { get; } = new();
#else
    public IKeyboardSimulator Keyboard => Simulation.SendInput.Keyboard;

    public IMouseSimulator Mouse => Simulation.SendInput.Mouse;
#endif

    /// <summary>
    /// Default timeout for operations in milliseconds
    /// </summary>
    public int DefaultTimeout { get; set; } = 10000;

    /// <summary>
    /// Default retry interval in milliseconds
    /// </summary>
    public int DefaultRetryInterval { get; set; } = 1000;

    public BvPage(CancellationToken cancellationToken = default)
    {
        _cancellationToken = cancellationToken;
    }

    /// <summary>
    /// 截图
    /// </summary>
    /// <returns></returns>
    public ImageRegion Screenshot()
    {
        return TaskControl.CaptureToRectArea();
    }

    /// <summary>
    /// 等待
    /// </summary>
    /// <param name="milliseconds"></param>
    /// <returns></returns>
    public async Task<BvPage> Wait(int milliseconds)
    {
        await TaskControl.Delay(milliseconds, _cancellationToken);
        return this;
    }

    /// <summary>
    /// 定位图片位置
    /// </summary>
    /// <param name="image"></param>
    /// <returns></returns>
    public BvLocator Locator(BvImage image)
    {
        return new BvLocator(image.ToRecognitionObject(), _cancellationToken);
    }

    /// <summary>
    /// 定位文本位置
    /// </summary>
    /// <param name="text"></param>
    /// <param name="rect"></param>
    /// <returns></returns>
    public BvLocator Locator(string text, Rect rect = default)
    {
        return Locator(new RecognitionObject
        {
            RecognitionType = RecognitionTypes.Ocr,
            RegionOfInterest = rect,
            Text = text
        });
    }


    /// <summary>
    /// 定位 RecognitionObject 代表的位置
    /// </summary>
    /// <param name="ro"></param>
    /// <returns></returns>
    public BvLocator Locator(RecognitionObject ro)
    {
        return new BvLocator(ro, _cancellationToken);
    }

    public BvLocator GetByText(string text = "", Rect rect = default)
    {
        return Locator(text, rect);
    }

    public BvLocator GetByImage(BvImage image)
    {
        return Locator(image);
    }


    public List<Region> Ocr(Rect rect = default)
    {
        return Locator(string.Empty, rect).FindAll();
    }


    /// <summary>
    /// 1080P 分辨率下点击坐标
    /// </summary>
    /// <param name="x"></param>
    /// <param name="y"></param>
    public void Click(double x, double y)
    {
        GameCaptureRegion.GameRegion1080PPosClick(x, y);
    }
}

#if BGI_PLATFORM_MAC
public sealed class BvKeyboard
{
    public BvKeyboard KeyDown(int windowsVirtualKey)
    {
        TaskControlPlatform.Current.KeyDown(windowsVirtualKey);
        return this;
    }

    public BvKeyboard KeyUp(int windowsVirtualKey)
    {
        TaskControlPlatform.Current.KeyUp(windowsVirtualKey);
        return this;
    }

    public BvKeyboard KeyPress(int windowsVirtualKey)
    {
        TaskControlPlatform.Current.PressKey(windowsVirtualKey);
        return this;
    }

    public BvKeyboard TextEntry(string text)
    {
        TaskControlPlatform.Current.InputText(text);
        return this;
    }
}

public sealed class BvMouse
{
    public BvMouse MoveMouseBy(int x, int y)
    {
        TaskControlPlatform.Current.MoveMouseBy(x, y);
        return this;
    }

    public BvMouse LeftButtonDown() { TaskControlPlatform.Current.LeftButtonDown(); return this; }
    public BvMouse LeftButtonUp() { TaskControlPlatform.Current.LeftButtonUp(); return this; }
    public BvMouse LeftButtonClick() { TaskControlPlatform.Current.LeftButtonClick(); return this; }
    public BvMouse RightButtonDown() { TaskControlPlatform.Current.RightButtonDown(); return this; }
    public BvMouse RightButtonUp() { TaskControlPlatform.Current.RightButtonUp(); return this; }
    public BvMouse RightButtonClick() { TaskControlPlatform.Current.RightButtonClick(); return this; }
    public BvMouse MiddleButtonDown() { TaskControlPlatform.Current.MiddleButtonDown(); return this; }
    public BvMouse MiddleButtonUp() { TaskControlPlatform.Current.MiddleButtonUp(); return this; }
    public BvMouse MiddleButtonClick() { TaskControlPlatform.Current.MiddleButtonClick(); return this; }

    public BvMouse VerticalScroll(int scrollAmountInClicks)
    {
        TaskControlPlatform.Current.VerticalScroll(scrollAmountInClicks);
        return this;
    }
}
#endif
