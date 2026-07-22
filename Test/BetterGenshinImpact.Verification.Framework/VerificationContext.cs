namespace BetterGenshinImpact.Verification.Framework;

public sealed class VerificationContext(TextWriter output)
{
    public TextWriter Output { get; } = output ?? throw new ArgumentNullException(nameof(output));

    public void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidDataException(message);
    }
}
