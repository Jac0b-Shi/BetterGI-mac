using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace BetterGenshinImpact.GameTask.AutoFight.Script;

public interface ICombatCommandScene
{
    ICombatCommandAvatar? SelectAvatar(string name);

    ICombatCommandAvatar SelectAvatar(int avatarIndex);
}

public interface ICombatScriptScene : ICombatCommandScene
{
    IReadOnlyCollection<ICombatCommandAvatar> GetAvatars();

    void BeforeTask(CancellationToken cancellationToken);
}

public interface ICombatCommandAvatar
{
    string Name { get; }

    bool IsSkillReady(bool printLog = false);

    Task WaitSkillCd(CancellationToken ct = default);

    void Switch();

    void UseSkill(bool hold = false);

    void UseBurst();

    void Attack(int ms = 0);

    void Charge(int ms = 0);

    void Walk(string key, int ms);

    void Wait(int ms);

    void Ready();

    void Dash(int ms = 0);

    void Jump();

    void MouseDown(string key = "left");

    void MouseUp(string key = "left");

    void Click(string key = "left");

    void MoveBy(int x, int y);

    void KeyDown(string key);

    void KeyUp(string key);

    void KeyPress(string key);

    void Scroll(int scrollAmountInClicks);
}
