namespace BetterGenshinImpact.Core.Abstractions.Recognition;

/// <summary>
/// DI-role interface for the Paddle OCR recognizer.
/// Separated from <see cref="IYapAutoPickTextRecognizer"/> so that
/// Microsoft DI can resolve each role unambiguously.
/// </summary>
public interface IPaddleAutoPickTextRecognizer : IAutoPickTextRecognizer
{
}
