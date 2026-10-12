#if BGI_PLATFORM_MAC
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.Core.Simulator.Extensions;
using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Input.Backends.Mac;

/// <summary>共享 InputHub 与既有 Wine/Quartz 会话使用同一个输入 owner，不创建第二套原生输入链。</summary>
public sealed class MacTaskControlInputBackend : IInputBackend
{
    private readonly Channel _channel = new();
    public InputBackendKind Kind { get; }
    public MacTaskControlInputBackend(InputBackendKind kind = InputBackendKind.MacWine) => Kind = kind;
    public IInputChannel Foreground => _channel;
    public IInputChannel Background => _channel;
    public void ReleaseAll() => _channel.ReleaseAll();
    // Attach 只能在空闲边界执行；切换不发送全局 key-up。
    public void Dispose() { }

    private sealed class Channel : InputChannelBase
    {
        private readonly object _actionsLock = new();
        private readonly HashSet<GIActions> _heldActions = [];
        private static ITaskControlPlatform Platform => TaskControlPlatform.Current;
        protected override void OnKeyDown(int key) => Platform.KeyDown(key);
        protected override void OnKeyUp(int key) => Platform.KeyUp(key);
        protected override void OnKeyPress(int key) => Platform.PressKey(key);
        protected override void OnMouseButton(InputMouseButton button, bool down)
        {
            switch (button)
            {
                case InputMouseButton.Left: if (down) Platform.LeftButtonDown(); else Platform.LeftButtonUp(); break;
                case InputMouseButton.Right: if (down) Platform.RightButtonDown(); else Platform.RightButtonUp(); break;
                case InputMouseButton.Middle: if (down) Platform.MiddleButtonDown(); else Platform.MiddleButtonUp(); break;
                default: throw new NotSupportedException("macOS input does not support side mouse buttons.");
            }
        }
        protected override void OnMouseClick(InputMouseButton button)
        {
            switch (button)
            {
                case InputMouseButton.Left: Platform.LeftButtonClick(); break;
                case InputMouseButton.Right: Platform.RightButtonClick(); break;
                case InputMouseButton.Middle: Platform.MiddleButtonClick(); break;
                default: throw new NotSupportedException("macOS input does not support side mouse buttons.");
            }
        }
        protected override void OnMoveBy(int dx, int dy) => Platform.MoveMouseBy(dx, dy);
        protected override void OnMoveTo(double x, double y) => DesktopRegionInputPlatform.Current.MoveMouseTo(
            (int)Math.Round(x * DesktopRegion.DisplayWidth / 65535),
            (int)Math.Round(y * DesktopRegion.DisplayHeight / 65535));
        protected override void OnScroll(int clicks) => Platform.VerticalScroll(clicks);
        public override void ReleaseAll()
        {
            base.ReleaseAll();
            lock (_actionsLock)
            {
                foreach (var action in _heldActions.ToArray())
                {
                    try { Platform.SimulateAction(action, KeyType.KeyUp); _heldActions.Remove(action); }
                    catch (Exception e) { Logger.LogDebug(e, "释放动作 {Action} 失败", action); }
                }
            }
        }
        public override IInputChannel SimulateAction(GIActions action, KeyType type = KeyType.KeyPress)
        {
            lock (_actionsLock)
            {
                Platform.SimulateAction(action, type);
                if (type == KeyType.KeyDown) _heldActions.Add(action);
                else _heldActions.Remove(action);
            }
            return this;
        }
    }
}
#endif
