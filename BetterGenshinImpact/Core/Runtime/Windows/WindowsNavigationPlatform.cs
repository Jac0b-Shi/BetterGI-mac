using BetterGenshinImpact.GameTask.AutoPathing;
using CommunityToolkit.Mvvm.Messaging;
using CommunityToolkit.Mvvm.Messaging.Messages;
using OpenCvSharp;

namespace BetterGenshinImpact.Core.Runtime.Windows;

public sealed class WindowsNavigationPlatform : INavigationPlatform
{
    public void PublishCurrentPosition(Point2f position) =>
        WeakReferenceMessenger.Default.Send(new PropertyChangedMessage<object>(
            typeof(Navigation), "SendCurrentPosition", new object(), position));
}
