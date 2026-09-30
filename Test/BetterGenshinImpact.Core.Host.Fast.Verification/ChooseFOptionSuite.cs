using BetterGenshinImpact.GameTask.Common.Job;
using BetterGenshinImpact.GameTask.Model.Area;
using BetterGenshinImpact.Verification.Framework;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class ChooseFOptionSuite : IVerificationSuite
{
    public string Name => "choose-f-option";
    public Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        using var first = new Region { X = 100, Y = 100, Width = 40, Height = 20, Text = "进入" };
        using var second = new Region { X = 140, Y = 100, Width = 40, Height = 20, Text = "秘境" };
        using var current = new Region { X = 100, Y = 150, Width = 80, Height = 20, Text = "其他选项" };
        var rows = ChooseFOptionTask.MergeCandidateRows([current, second, first]);
        try
        {
            context.Require(rows.Count == 2 && rows[0].Text == "进入秘境" &&
                ChooseFOptionTask.GetScrollClicks(rows, new Rect(70, 150, 20, 20), "进入 秘境") == 1,
                "OCR fragments changed the candidate order or scroll direction.");
            context.Require(ChooseFOptionTask.GetScrollClicks([rows[0], rows[0], rows[1]],
                new Rect(70, 150, 20, 20), "进入秘境") is null,
                "An ambiguous OCR target allowed an interaction key press.");
        }
        finally { foreach (var row in rows) row.Dispose(); }
        return Task.CompletedTask;
    }
}
