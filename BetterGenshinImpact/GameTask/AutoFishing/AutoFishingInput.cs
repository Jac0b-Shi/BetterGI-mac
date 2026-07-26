using BetterGenshinImpact.Core.Simulator.Extensions;
using BetterGenshinImpact.GameTask.Common;

namespace BetterGenshinImpact.GameTask.AutoFishing;

public interface IAutoFishingInput
{
    void MoveMouseBy(int x, int y);
    void LeftButtonDown();
    void LeftButtonUp();
    void LeftButtonClick();
    void RightButtonClick();
    bool IsLeftButtonDown();
    void PressEscape();
    void PressInteraction();
    void SetMoveForward(bool isDown);
    void SetMoveBackward(bool isDown);
}

public sealed class TaskControlAutoFishingInput : IAutoFishingInput
{
    public void MoveMouseBy(int x, int y) => TaskControlPlatform.Current.MoveMouseBy(x, y);
    public void LeftButtonDown() => TaskControlPlatform.Current.LeftButtonDown();
    public void LeftButtonUp() => TaskControlPlatform.Current.LeftButtonUp();
    public void LeftButtonClick() => TaskControlPlatform.Current.LeftButtonClick();
    public void RightButtonClick() => TaskControlPlatform.Current.RightButtonClick();
    public bool IsLeftButtonDown() =>
        TaskControlPlatform.Current.IsActionKeyDown(GIActions.NormalAttack);
    public void PressEscape() => TaskControlPlatform.Current.PressEscape();
    public void PressInteraction() => TaskControlPlatform.Current.SimulateAction(
        GIActions.PickUpOrInteract, KeyType.KeyPress);
    public void SetMoveForward(bool isDown) => TaskControlPlatform.Current.SimulateAction(
        GIActions.MoveForward, isDown ? KeyType.KeyDown : KeyType.KeyUp);
    public void SetMoveBackward(bool isDown) => TaskControlPlatform.Current.SimulateAction(
        GIActions.MoveBackward, isDown ? KeyType.KeyDown : KeyType.KeyUp);
}
