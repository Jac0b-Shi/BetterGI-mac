using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Model;
using Microsoft.Extensions.Localization;
using System;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsTaskParameterPlatform : ITaskParameterPlatform
{
    public string GameCultureInfoName => TaskContext.Instance().Config.OtherConfig.GameCultureInfoName;
    public IStringLocalizer<T> GetStringLocalizer<T>() =>
        App.GetService<IStringLocalizer<T>>() ?? throw new InvalidOperationException(
            $"String localizer for {typeof(T).FullName} is not registered.");
}
