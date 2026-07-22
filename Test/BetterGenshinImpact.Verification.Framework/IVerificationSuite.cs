namespace BetterGenshinImpact.Verification.Framework;

public interface IVerificationSuite
{
    string Name { get; }
    Task RunAsync(VerificationContext context, CancellationToken cancellationToken);
}
