#if !BGI_PLATFORM_MAC
using BetterGenshinImpact.Core.Simulator;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoFight.Model;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.Helpers;
using BetterGenshinImpact.ViewModel.Pages;
using Fischless.WindowsInput;
using Microsoft.Extensions.Logging;
using System;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using Vanara.PInvoke;
using static Vanara.PInvoke.User32;

namespace BetterGenshinImpact.Core.Script.Dependence;

public static partial class GlobalMethod
{
    static GlobalMethod() => Configure(new WindowsGlobalMethodRuntime());

    private sealed class WindowsGlobalMethodRuntime : IGlobalMethodRuntime
    {
        public CancellationToken CancellationToken => CancellationContext.Instance.Cts.Token;
        public double DpiScale => TaskContext.Instance().DpiScale;

        public void KeyDown(string key)
        {
            var vk = KeyBindingsSettingsPageViewModel.MappingKey(ToVk(key));
            switch (key)
            {
                case "VK_LBUTTON": Simulation.SendInput.Mouse.LeftButtonDown(); break;
                case "VK_RBUTTON": Simulation.SendInput.Mouse.RightButtonDown(); break;
                case "VK_MBUTTON": Simulation.SendInput.Mouse.MiddleButtonDown(); break;
                case "VK_XBUTTON1": Simulation.SendInput.Mouse.XButtonDown(0x0001); break;
                case "VK_XBUTTON2": Simulation.SendInput.Mouse.XButtonDown(0x0001); break;
                default:
                    if (InputBuilder.IsExtendedKey(vk)) Simulation.SendInput.Keyboard.KeyDown(false, vk);
                    else Simulation.SendInput.Keyboard.KeyDown(vk);
                    break;
            }
        }

        public void KeyUp(string key)
        {
            var vk = KeyBindingsSettingsPageViewModel.MappingKey(ToVk(key));
            switch (key)
            {
                case "VK_LBUTTON": Simulation.SendInput.Mouse.LeftButtonUp(); break;
                case "VK_RBUTTON": Simulation.SendInput.Mouse.RightButtonUp(); break;
                case "VK_MBUTTON": Simulation.SendInput.Mouse.MiddleButtonUp(); break;
                case "VK_XBUTTON1": Simulation.SendInput.Mouse.XButtonUp(0x0001); break;
                case "VK_XBUTTON2": Simulation.SendInput.Mouse.XButtonUp(0x0001); break;
                default:
                    if (InputBuilder.IsExtendedKey(vk)) Simulation.SendInput.Keyboard.KeyUp(false, vk);
                    else Simulation.SendInput.Keyboard.KeyUp(vk);
                    break;
            }
        }

        public void KeyPress(string key)
        {
            var vk = KeyBindingsSettingsPageViewModel.MappingKey(ToVk(key));
            switch (key)
            {
                case "VK_LBUTTON": Simulation.SendInput.Mouse.LeftButtonClick(); break;
                case "VK_RBUTTON": Simulation.SendInput.Mouse.RightButtonClick(); break;
                case "VK_MBUTTON": Simulation.SendInput.Mouse.MiddleButtonClick(); break;
                case "VK_XBUTTON1": Simulation.SendInput.Mouse.XButtonClick(0x0001); break;
                case "VK_XBUTTON2": Simulation.SendInput.Mouse.XButtonClick(0x0001); break;
                default:
                    if (InputBuilder.IsExtendedKey(vk)) Simulation.SendInput.Keyboard.KeyPress(false, vk);
                    else Simulation.SendInput.Keyboard.KeyPress(vk);
                    break;
            }
        }

        public void MoveMouseBy(int x, int y) => Simulation.SendInput.Mouse.MoveMouseBy(x, y);

        public void MoveMouseToGameCoordinate(int x, int y, int gameWidth, int gameHeight) =>
            GameCaptureRegion.GameRegionMove((_, scaleTo1080P) =>
            {
                var scale = 1920.0 / gameWidth;
                return (x * scale * scaleTo1080P, y * scale * scaleTo1080P);
            });

        public void ClickGameCoordinate(int x, int y, int gameWidth, int gameHeight)
        {
            MoveMouseToGameCoordinate(x, y, gameWidth, gameHeight);
            LeftButtonClick();
        }

        public void LeftButtonClick() => Simulation.SendInput.Mouse.LeftButtonDown().Sleep(60).LeftButtonUp();
        public void LeftButtonDown() => Simulation.SendInput.Mouse.LeftButtonDown();
        public void LeftButtonUp() => Simulation.SendInput.Mouse.LeftButtonUp();
        public void RightButtonClick() => Simulation.SendInput.Mouse.RightButtonDown().Sleep(60).RightButtonUp();
        public void RightButtonDown() => Simulation.SendInput.Mouse.RightButtonDown();
        public void RightButtonUp() => Simulation.SendInput.Mouse.RightButtonUp();
        public void MiddleButtonClick() => Simulation.SendInput.Mouse.MiddleButtonClick();
        public void MiddleButtonDown() => Simulation.SendInput.Mouse.MiddleButtonDown();
        public void MiddleButtonUp() => Simulation.SendInput.Mouse.MiddleButtonUp();
        public void VerticalScroll(int amount) => Simulation.SendInput.Mouse.VerticalScroll(amount);
        public ImageRegion CaptureGameRegion() => TaskControl.CaptureToRectArea();

        public string[] GetAvatars()
        {
            var combatScenes = new CombatScenes().InitializeTeam(CaptureGameRegion());
            var avatars = combatScenes.GetAvatars();
            return avatars.Count > 0 ? avatars.Select(avatar => avatar.Name).ToArray() : [];
        }

        public void InputText(string text)
        {
            try
            {
                UIDispatcherHelper.Invoke(() => Clipboard.SetDataObject(text));
                Simulation.SendInput.Keyboard.KeyDown(false, VK.VK_CONTROL);
                Thread.Sleep(20);
                Simulation.SendInput.Keyboard.KeyPress(VK.VK_V);
                Thread.Sleep(20);
                Simulation.SendInput.Keyboard.KeyUp(false, VK.VK_CONTROL);
                Thread.Sleep(100);
            }
            catch (Exception ex)
            {
                TaskControl.Logger.LogDebug("输入文本时发生错误: {Msg}", ex.Message);
            }
        }

        private static User32.VK ToVk(string key)
        {
            try { return User32Helper.ToVk(key); }
            catch { throw new ArgumentException($"键盘编码必须是VirtualKeyCodes枚举中的值，当前传入的 {key} 不合法"); }
        }
    }
}
#endif
