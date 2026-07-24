using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.GameTask.AutoMusicGame;
using BetterGenshinImpact.Verification.Framework;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Newtonsoft.Json.Linq;
using System.Net;
using System.Net.Sockets;
using System.Runtime.Versioning;
using System.Text;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class NotificationRoutingSuite : IVerificationSuite
{
    public string Name => "notification-routing";

    [SupportedOSPlatform("macos")]
    public async Task RunAsync(
        VerificationContext context,
        CancellationToken cancellationToken)
    {
        var root = Path.Combine(
            Path.GetTempPath(), $"bettergi-notification-routing-{Guid.NewGuid():N}");
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        try
        {
            var layout = new RuntimeLayout(root);
            layout.EnsureCreated();
            listener.Start();
            var endpoint =
                $"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}/notify";
            await File.WriteAllTextAsync(
                Path.Combine(layout.UserPath, "config.json"),
                $$"""
                  {
                    "notificationConfig": {
                      "includeScreenShot": false,
                      "jsNotificationEnabled": true,
                      "windowsUwpNotificationEnabled": false,
                      "notificationEventSubscribe": "album.start,task.error,group.start",
                      "webhookEnabled": true,
                      "webhookEndpoint": "{{endpoint}}",
                      "webhookSendTo": "verification"
                    }
                  }
                  """,
                cancellationToken);

            using var loggerFactory = LoggerFactory.Create(_ => { });
            using var notificationSettings = new NotificationSettingsCatalog(
                layout,
                new PlatformCallbackChannel(),
                "verification",
                cancellationToken,
                () => null,
                loggerFactory.CreateLogger<NotificationSettingsCatalog>());

            var album = new MacAutoAlbumRuntimePlatform(
                () => throw new InvalidOperationException(
                    "Notification routing must not read game metrics."),
                NullLogger<AutoAlbumTask>.Instance);
            var albumRequest = ReadHttpRequestBodyAsync(
                listener, cancellationToken);
            album.Notify(AutoAlbumNotification.Start, "自动音游专辑启动");
            RequirePayload(
                context,
                JObject.Parse(await albumRequest),
                "album.start",
                0,
                "自动音游专辑启动");

            var callbacks = new PlatformCallbackChannel();
            var foreground = new ForegroundInputCoordinator(
                callbacks,
                "verification",
                cancellationToken,
                focusProbe: () => true);
            var taskRunner = new MacTaskRunnerPlatform(
                callbacks,
                "verification",
                cancellationToken,
                NullLogger.Instance,
                NullLogger.Instance,
                foreground);
            var taskErrorRequest = ReadHttpRequestBodyAsync(
                listener, cancellationToken);
            taskRunner.NotifyError(
                "独立任务异常",
                new InvalidOperationException("verification failure"));
            var taskErrorPayload = JObject.Parse(await taskErrorRequest);
            context.Require(
                taskErrorPayload.Value<string>("event") == "task.error" &&
                taskErrorPayload.Value<int>("result") == 1 &&
                taskErrorPayload.Value<string>("message")!
                    .Contains("verification failure", StringComparison.Ordinal),
                $"TaskRunner notification bypassed the shared notifier chain: {taskErrorPayload}");

            var scriptHostServices = new MacScriptHostServices(loggerFactory);
            var gameTaskManager = new MacGameTaskManagerPlatform(
                layout,
                callbacks,
                "verification",
                cancellationToken,
                loggerFactory);
            var scriptService = new MacScriptServicePlatform(
                layout,
                NullLogger.Instance,
                scriptHostServices,
                callbacks,
                "verification",
                cancellationToken,
                new SharedCaptureRingReader(layout, allowFileFixture: true),
                gameTaskManager,
                foreground);
            var groupRequest = ReadHttpRequestBodyAsync(
                listener, cancellationToken);
            scriptService.NotifyGroupStart("验证组");
            RequirePayload(
                context,
                JObject.Parse(await groupRequest),
                "group.start",
                0,
                "配置组验证组启动");

            album.Notify(AutoAlbumNotification.End, "不应发送");
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                cancellationToken);
            timeout.CancelAfter(TimeSpan.FromMilliseconds(300));
            try
            {
                using var unexpected = await listener.AcceptTcpClientAsync(
                    timeout.Token);
                context.Require(
                    false,
                    "Notification subscription filtering allowed an unselected album.end event.");
            }
            catch (OperationCanceledException)
                when (timeout.IsCancellationRequested &&
                      !cancellationToken.IsCancellationRequested)
            {
            }
        }
        finally
        {
            listener.Stop();
            if (Directory.Exists(root))
                Directory.Delete(root, recursive: true);
        }
    }

    private static void RequirePayload(
        VerificationContext context,
        JObject payload,
        string eventCode,
        int result,
        string message)
    {
        context.Require(
            payload.Value<string>("send_to") == "verification" &&
            payload.Value<string>("event") == eventCode &&
            payload.Value<int>("result") == result &&
            payload.Value<string>("message") == message,
            $"Shared notification payload was unexpected: {payload}");
    }

    private static async Task<string> ReadHttpRequestBodyAsync(
        TcpListener listener,
        CancellationToken cancellationToken)
    {
        using var client = await listener.AcceptTcpClientAsync(cancellationToken);
        await using var stream = client.GetStream();
        using var reader = new StreamReader(
            stream,
            Encoding.UTF8,
            detectEncodingFromByteOrderMarks: false,
            leaveOpen: true);
        var contentLength = 0;
        while (await reader.ReadLineAsync(cancellationToken) is { } line &&
               line.Length > 0)
        {
            const string header = "Content-Length:";
            if (line.StartsWith(header, StringComparison.OrdinalIgnoreCase))
                contentLength = int.Parse(line[header.Length..].Trim());
        }
        var buffer = new char[contentLength];
        var read = 0;
        while (read < buffer.Length)
        {
            var count = await reader.ReadAsync(
                buffer.AsMemory(read, buffer.Length - read),
                cancellationToken);
            if (count == 0)
                throw new EndOfStreamException(
                    "Webhook request ended before its declared body length.");
            read += count;
        }
        var response = Encoding.ASCII.GetBytes(
            "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        await stream.WriteAsync(response, cancellationToken);
        await stream.FlushAsync(cancellationToken);
        return new string(buffer);
    }
}
