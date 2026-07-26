using BetterGenshinImpact.Helpers;
using System;
using System.Collections.Generic;

namespace BetterGenshinImpact.GameTask.AutoFight.Script;

public partial class CombatCommand
{
    public string Name { get; set; }
    public Method Method { get; set; }
    public List<string>? Args { get; set; }
    public List<int> ActivatingRound { get; set; } = [];

    public CombatCommand(string name, string command)
    {
        Name = name.Trim();
        command = command.Trim();
        var startIndex = command.IndexOf('(');
        if (startIndex > 0)
        {
            var endIndex = command.IndexOf(')');
            var method = command[..startIndex].Trim();
            Method = Method.GetEnumByCode(method);
            var parameters = command.Substring(startIndex + 1, endIndex - startIndex - 1);
            Args = [..parameters.Split(',', StringSplitOptions.TrimEntries)];
        }
        else
        {
            Method = Method.GetEnumByCode(command);
            Args = [];
        }

        if (Method == Method.Walk)
        {
            AssertUtils.IsTrue(Args.Count == 2, "walk方法必须有两个入参，第一个参数是方向，第二个参数是行走时间。例：walk(s, 0.2)");
            AssertUtils.IsTrue(double.Parse(Args[1]) > 0, "行走时间必须大于0");
        }
        else if (Method == Method.W || Method == Method.A || Method == Method.S || Method == Method.D)
        {
            AssertUtils.IsTrue(Args.Count == 1, "w/a/s/d方法必须有一个入参，代表行走时间。例：d(0.5)");
        }
        else if (Method == Method.MoveBy)
        {
            AssertUtils.IsTrue(Args.Count == 2, "moveby方法必须有两个入参，分别是x和y。例：moveby(100, 100))");
        }
        else if (Method == Method.KeyDown || Method == Method.KeyUp || Method == Method.KeyPress)
        {
            AssertUtils.IsTrue(Args.Count == 1, $"{Method.Alias[0]}方法必须有一个入参，代表按键");
            try
            {
                CombatCommandPlatform.Current.ValidateKeyName(Args[0]);
            }
            catch
            {
                throw new ArgumentException($"{Method.Alias[0]}方法的入参必须是VirtualKeyCodes枚举中的值，当前入参 {Args[0]} 不合法");
            }
        }
        else if (Method == Method.Scroll)
        {
            AssertUtils.IsTrue(Args.Count == 1, "scroll方法必须有一个入参，代表滚动格数。例：scroll(1) 或 scroll(-1)");
            AssertUtils.IsTrue(int.TryParse(Args[0], out _), "滚动格数必须是整数");
        }
    }

    public override string ToString() => $"<CombatCommand {Name}, {Method}({Args}) (rounds {ActivatingRound})>";
}
