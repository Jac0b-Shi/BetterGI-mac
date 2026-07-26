namespace BetterGenshinImpact.Platform.Abstractions;

public interface IUserInteractionService
{
    void ShowError(string message);
    void ShowWarning(string message);
}
