#if !BGI_PLATFORM_MAC
using BetterGenshinImpact.Core.Simulator;
using BetterGenshinImpact.GameTask.Model.Area.Converter;
using BetterGenshinImpact.Helpers;
using Fischless.WindowsInput;
using OpenCvSharp;

namespace BetterGenshinImpact.GameTask.Model.Area;

/// <summary>Windows desktop-region implementation retained from upstream.</summary>
public class DesktopRegion : Region
{
    private readonly IMouseSimulator mouse;

    public DesktopRegion(int w, int h, IMouseSimulator? iMouse = null) : base(0, 0, w, h) => mouse = iMouse ?? Simulation.SendInput.Mouse;
    public DesktopRegion() : base(0, 0, PrimaryScreen.WorkingArea.Width, PrimaryScreen.WorkingArea.Height) => mouse = Simulation.SendInput.Mouse;
    public DesktopRegion(IMouseSimulator mouse) : base(0, 0, PrimaryScreen.WorkingArea.Width, PrimaryScreen.WorkingArea.Height) => this.mouse = mouse;

    public void DesktopRegionClick(int x, int y, int w, int h) => mouse.MoveMouseTo((x + w / 2d) * 65535 / Width, (y + h / 2d) * 65535 / Height).LeftButtonDown().Sleep(50).LeftButtonUp().Sleep(50);
    public void DesktopRegionMove(int x, int y, int w, int h) => mouse.MoveMouseTo((x + w / 2d) * 65535 / Width, (y + h / 2d) * 65535 / Height);
    public static void DesktopRegionClick(double x, double y) => Simulation.SendInput.Mouse.MoveMouseTo(x * 65535 / PrimaryScreen.WorkingArea.Width, y * 65535 / PrimaryScreen.WorkingArea.Height).LeftButtonDown().Sleep(50).LeftButtonUp().Sleep(50);
    public static void DesktopRegionMove(double x, double y) => Simulation.SendInput.Mouse.MoveMouseTo(x * 65535 / PrimaryScreen.WorkingArea.Width, y * 65535 / PrimaryScreen.WorkingArea.Height);
    public static void DesktopRegionMoveBy(double x, double y) => Simulation.SendInput.Mouse.MoveMouseBy((int)x, (int)y);
    public GameCaptureRegion Derive(Mat captureMat, int x, int y) => new(captureMat, x, y, this, new TranslationConverter(x, y));
}
#else
using BetterGenshinImpact.GameTask.Model.Area.Converter;
using OpenCvSharp;
using System;

namespace BetterGenshinImpact.GameTask.Model.Area;

/// <summary>macOS Core implementation; input is supplied by composition.</summary>
public class DesktopRegion : Region
{
    public static int DisplayWidth { get; set; }
    public static int DisplayHeight { get; set; }
    public DesktopRegion(int w, int h) : base(0, 0, w, h) { }
    public DesktopRegion() : this(DisplayWidth, DisplayHeight) { if (DisplayWidth == 0 || DisplayHeight == 0) throw new InvalidOperationException("Desktop size is not initialized."); }
    public void DesktopRegionClick(int x, int y, int w, int h) => DesktopRegionInputPlatform.Current.LeftClick(x + w / 2, y + h / 2);
    public void DesktopRegionMove(int x, int y, int w, int h) => DesktopRegionInputPlatform.Current.MoveMouseTo(x + w / 2, y + h / 2);
    public static void DesktopRegionClick(double x, double y) => DesktopRegionInputPlatform.Current.LeftClick((int)Math.Round(x), (int)Math.Round(y));
    public static void DesktopRegionMove(double x, double y) => DesktopRegionInputPlatform.Current.MoveMouseTo((int)Math.Round(x), (int)Math.Round(y));
    public static void DesktopRegionMoveBy(double x, double y) => DesktopRegionInputPlatform.Current.MoveMouseBy((int)x, (int)y);
    public GameCaptureRegion Derive(Mat captureMat, int x, int y) => new(captureMat, x, y, this, new TranslationConverter(x, y));
}
#endif
