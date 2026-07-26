using System;
using TimeSpan = System.TimeSpan;

namespace BetterGenshinImpact.GameTask.AutoFight.Script;

public partial class CombatCommand
{
    public void Execute(ICombatCommandScene combatScenes, CombatCommand? lastCommand = null)
    {
        ICombatCommandAvatar? avatar;
        if (Name == CombatScriptParser.CurrentAvatarName)
        {
            avatar = combatScenes.SelectAvatar(1);
        }
        else
        {
            // 其余情况要进行角色切换
            avatar = combatScenes.SelectAvatar(Name);
            if (avatar == null)
            {
                return;
            }

            if (lastCommand != null && lastCommand.Name != Name)
            {
                // 上一个命令和当前命令不是同一个角色，直接切换角色
                avatar.Switch();
            }
            else
            {
                // 非宏类脚本，等待切换角色成功
                if (Method != Method.Wait
                    && Method != Method.MouseDown
                    && Method != Method.MouseUp
                    && Method != Method.Click
                    && Method != Method.MoveBy
                    && Method != Method.KeyDown
                    && Method != Method.KeyUp
                    && Method != Method.KeyPress
                    && Method != Method.Scroll
                    && Method != Method.Ready)
                {
                    avatar.Switch();
                }
            }
        }
        Execute(avatar);
    }

    public void Execute(ICombatCommandAvatar avatar)
    {
        if (Method == Method.Skill)
        {
            var hold = Args != null && Args.Contains("hold");
            var wait = Args != null && Args.Contains("wait");
            var fast = Args != null && Args.Contains("fast");
            if (fast)
            {
                // 快速跳过e
                if (!avatar.IsSkillReady(true))
                {
                    return;
                }
            }
            else if (wait)
            {
                // 等待e结束,同步等待
                avatar.WaitSkillCd().Wait();
            }

            avatar.UseSkill(hold);
        }
        else if (Method == Method.Burst)
        {
            avatar.UseBurst();
        }
        else if (Method == Method.Attack)
        {
            if (Args is { Count: > 0 })
            {
                var s = double.Parse(Args![0]);
                avatar.Attack((int)TimeSpan.FromSeconds(s).TotalMilliseconds);
            }
            else
            {
                avatar.Attack();
            }
        }
        else if (Method == Method.Charge)
        {
            if (Args is { Count: > 0 })
            {
                var s = double.Parse(Args![0]);
                avatar.Charge((int)TimeSpan.FromSeconds(s).TotalMilliseconds);
            }
            else
            {
                avatar.Charge();
            }
        }
        else if (Method == Method.Walk)
        {
            var s = double.Parse(Args![1]);
            avatar.Walk(Args![0], (int)TimeSpan.FromSeconds(s).TotalMilliseconds);
        }
        else if (Method == Method.W)
        {
            var s = double.Parse(Args![0]);
            avatar.Walk("w", (int)TimeSpan.FromSeconds(s).TotalMilliseconds);
        }
        else if (Method == Method.A)
        {
            var s = double.Parse(Args![0]);
            avatar.Walk("a", (int)TimeSpan.FromSeconds(s).TotalMilliseconds);
        }
        else if (Method == Method.S)
        {
            var s = double.Parse(Args![0]);
            avatar.Walk("s", (int)TimeSpan.FromSeconds(s).TotalMilliseconds);
        }
        else if (Method == Method.D)
        {
            var s = double.Parse(Args![0]);
            avatar.Walk("d", (int)TimeSpan.FromSeconds(s).TotalMilliseconds);
        }
        else if (Method == Method.Wait)
        {
            var s = double.Parse(Args![0]);
            avatar.Wait((int)TimeSpan.FromSeconds(s).TotalMilliseconds);
        }
        else if (Method == Method.Ready)
        {
            avatar.Ready();
        }
        else if (Method == Method.Check)
        {
            // check动作在AutoFightTask主循环中处理，此处不做任何操作
        }
        else if (Method == Method.Aim)
        {
            throw new NotImplementedException();
        }
        else if (Method == Method.Dash)
        {
            if (Args is { Count: > 0 })
            {
                var s = double.Parse(Args![0]);
                avatar.Dash((int)TimeSpan.FromSeconds(s).TotalMilliseconds);
            }
            else
            {
                avatar.Dash();
            }
        }
        else if (Method == Method.Jump)
        {
            avatar.Jump();
        }
        // 宏
        else if (Method == Method.MouseDown)
        {
            if (Args is { Count: > 0 })
            {
                avatar.MouseDown(Args![0]);
            }
            else
            {
                avatar.MouseDown();
            }
        }
        else if (Method == Method.MouseUp)
        {
            if (Args is { Count: > 0 })
            {
                avatar.MouseUp(Args![0]);
            }
            else
            {
                avatar.MouseUp();
            }
        }
        else if (Method == Method.Click)
        {
            if (Args is { Count: > 0 })
            {
                avatar.Click(Args![0]);
            }
            else
            {
                avatar.Click();
            }
        }
        else if (Method == Method.MoveBy)
        {
            if (Args is { Count: 2 })
            {
                var x = int.Parse(Args![0]);
                var y = int.Parse(Args[1]);
                avatar.MoveBy(x, y);
            }
            else
            {
                throw new ArgumentException("moveby方法必须有两个入参，分别是x和y。例：moveby(100, 100)");
            }
        }
        else if (Method == Method.KeyDown)
        {
            avatar.KeyDown(Args![0]);
        }
        else if (Method == Method.KeyUp)
        {
            avatar.KeyUp(Args![0]);
        }
        else if (Method == Method.KeyPress)
        {
            avatar.KeyPress(Args![0]);
        }
        else if (Method == Method.Scroll)
        {
            avatar.Scroll(int.Parse(Args![0]));
        }
        else if (Method == Method.Round)
        {
            // 作为回合标记使用，不做任何操作
        }
        else
        {
            throw new NotImplementedException();
        }
    }
}
