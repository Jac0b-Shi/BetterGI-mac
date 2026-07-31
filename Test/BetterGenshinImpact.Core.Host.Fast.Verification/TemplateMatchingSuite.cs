using BetterGenshinImpact.Core.Recognition.OpenCv;
using BetterGenshinImpact.Verification.Framework;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class TemplateMatchingSuite : IVerificationSuite
{
    public string Name => "template-matching";

    public Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        using var source = Mat.Zeros(32, 32, MatType.CV_8UC1).ToMat();
        using var template = new Mat(3, 3, MatType.CV_8UC1, Scalar.Black);
        template.Set(0, 0, (byte)255);
        template.Set(1, 1, (byte)180);
        template.Set(2, 0, (byte)90);
        using (var first = new Mat(source, new Rect(3, 4, 3, 3)))
        using (var second = new Mat(source, new Rect(22, 19, 3, 3)))
        {
            template.CopyTo(first);
            template.CopyTo(second);
        }

        var matches = MatchTemplateHelper.FindMatches(
            source,
            template,
            TemplateMatchModes.CCoeffNormed,
            null,
            0.99,
            8);

        context.Require(
            matches.Count == 2 &&
            matches.Any(match => match.Location == new Point(3, 4)) &&
            matches.Any(match => match.Location == new Point(22, 19)) &&
            matches.All(match => match.Score >= 0.99),
            "Optimized template matching did not preserve distinct locations and scores.");
        return Task.CompletedTask;
    }
}
