using BetterGenshinImpact.GameTask.AutoPick;

namespace BetterGenshinImpact.Core.Abstractions.Runtime;

/// <summary>
/// AutoPick configuration accessor.
/// <para>
/// <c>AutoPickConfig</c> returns the same mutable reference as the upstream config object.
/// Consumers that write back (e.g. <c>AutoPickConfig.PickKey = "F"</c> on load failure)
/// do so on the canonical instance — no defensive copy.
/// </para>
/// </summary>
public interface IAutoPickConfigProvider
{
    AutoPickConfig AutoPickConfig { get; }
}
