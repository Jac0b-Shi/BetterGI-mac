using BetterGenshinImpact.Core.Recognition;

namespace BetterGenshinImpact.Core.Abstractions.Recognition;

/// <summary>
/// DI-role interface for the Yap (SVTR) recognizer.
/// Separated from <see cref="IPaddleAutoPickTextRecognizer"/> so that
/// Microsoft DI can resolve each role unambiguously.
/// </summary>
public interface IYapAutoPickTextRecognizer : IAutoPickTextRecognizer
{
}
