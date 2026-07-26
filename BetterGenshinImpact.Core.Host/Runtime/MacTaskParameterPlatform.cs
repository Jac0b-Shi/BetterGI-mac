using BetterGenshinImpact.Core.Infrastructure;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Localization;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class MacTaskParameterPlatform(string gameCultureInfoName) : ITaskParameterPlatform
{
    public string GameCultureInfoName { get; } = gameCultureInfoName;
    public IStringLocalizer<T> GetStringLocalizer<T>() => new EmbeddedResourceStringLocalizer<T>();
}
