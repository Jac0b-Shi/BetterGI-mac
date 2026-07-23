using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Service.Notification;
using BetterGenshinImpact.Service.Notification.Model;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using BetterGenshinImpact.Service.Notifier;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class NotificationSettingsCatalog(
    RuntimeLayout layout,
    PlatformCallbackChannel callbacks,
    string sessionToken,
    CancellationToken cancellationToken,
    ILogger<NotificationSettingsCatalog> logger)
    : INotificationRuntimePlatform, IDisposable
{
    private readonly object _lock = new();
    private readonly HttpClient _httpClient = new()
    {
        Timeout = TimeSpan.FromSeconds(30),
    };
    private MacScriptHostServices? _scriptHostServices;

    public void AttachScriptHostServices(MacScriptHostServices services)
    {
        _scriptHostServices = services ?? throw new ArgumentNullException(nameof(services));
        services.SetJsNotificationEnabled(ReadConfig().JsNotificationEnabled);
        services.SetNotificationEmitter(EmitScriptNotification);
    }

    public object Get()
    {
        lock (_lock)
            return Describe(ReadConfigLocked());
    }

    public object Save(JObject settings)
    {
        var jsEnabled = RequiredBoolean(settings, "jsNotificationEnabled");
        var nativeEnabled = RequiredBoolean(settings, "macOSNotificationEnabled");
        var eventSubscribe = settings.Value<string>("notificationEventSubscribe")
            ?? throw new ArgumentException("notificationEventSubscribe is required.");
        var webhookEnabled = RequiredBoolean(settings, "webhookEnabled");
        var webhookEndpoint = settings.Value<string>("webhookEndpoint")
            ?? throw new ArgumentException("webhookEndpoint is required.");
        var webhookSendTo = settings.Value<string>("webhookSendTo")
            ?? throw new ArgumentException("webhookSendTo is required.");
        var normalizedEvents = NormalizeKnownEventCodes(eventSubscribe);
        if (webhookEnabled &&
            (!Uri.TryCreate(webhookEndpoint, UriKind.Absolute, out var endpoint) ||
             endpoint.Scheme is not ("http" or "https")))
        {
            throw new ArgumentException(
                "webhookEndpoint must be an absolute HTTP or HTTPS URL when Webhook is enabled.");
        }

        lock (_lock)
        {
            var root = LoadRoot();
            var notification = root["notificationConfig"] as JsonObject ?? [];
            notification["jsNotificationEnabled"] = jsEnabled;
            notification["windowsUwpNotificationEnabled"] = nativeEnabled;
            notification["notificationEventSubscribe"] = normalizedEvents;
            notification["webhookEnabled"] = webhookEnabled;
            notification["webhookEndpoint"] = webhookEndpoint.Trim();
            notification["webhookSendTo"] = webhookSendTo;
            root["notificationConfig"] = notification;
            SaveRoot(root);

            var config = notification.Deserialize<NotificationConfig>(ConfigJson.Options)
                ?? new NotificationConfig();
            _scriptHostServices?.SetJsNotificationEnabled(jsEnabled);
            return Describe(config);
        }
    }

    public async Task<object> TestAsync(string channel)
    {
        var config = ReadConfig();
        var data = new BaseNotificationData
        {
            Event = NotificationEvent.Test.Code,
            Result = NotificationEventResult.Success,
            Message = "这是一条 BetterGI 测试通知。",
        };
        switch (channel)
        {
            case "native":
                if (!config.WindowsUwpNotificationEnabled)
                    throw new InvalidOperationException("macOS 通知尚未启用。");
                await EmitNativeAsync(data);
                break;
            case "webhook":
                if (!config.WebhookEnabled)
                    throw new InvalidOperationException("Webhook 通知尚未启用。");
                await new WebhookNotifier(_httpClient, config).SendAsync(data);
                break;
            default:
                throw new ArgumentException($"Unknown notification channel: {channel}");
        }
        return new { channel, sent = true };
    }

    public void Send(BaseNotificationData notificationData)
    {
        ArgumentNullException.ThrowIfNull(notificationData);
        _ = Task.Run(async () =>
        {
            try
            {
                await DispatchAsync(notificationData);
            }
            catch (Exception exception)
            {
                logger.LogWarning(
                    exception,
                    "Notification event {Event} failed.",
                    notificationData.Event);
            }
        });
    }

    public void Dispose()
    {
        _httpClient.Dispose();
        GC.SuppressFinalize(this);
    }

    private void EmitScriptNotification(ScriptNotificationKind kind, string message)
    {
        var eventCode = kind == ScriptNotificationKind.Error
            ? NotificationEvent.JsError.Code
            : NotificationEvent.JsCustom.Code;
        Send(new BaseNotificationData
        {
            Event = eventCode,
            Result = kind == ScriptNotificationKind.Error
                ? NotificationEventResult.Fail
                : NotificationEventResult.Success,
            Message = message,
        });
    }

    private async Task DispatchAsync(BaseNotificationData notificationData)
    {
        var config = ReadConfig();
        if (!NotificationEventSubscriptionHelper.ShouldSendNotification(
                config.NotificationEventSubscribe,
                notificationData.Event))
        {
            logger.LogDebug(
                "Notification event {Event} was filtered by subscription settings.",
                notificationData.Event);
            return;
        }

        var deliveries = new List<Task>();
        if (config.WindowsUwpNotificationEnabled)
            deliveries.Add(EmitNativeAsync(notificationData));
        if (config.WebhookEnabled)
        {
            deliveries.Add(SendWebhookAsync(config, notificationData));
        }
        await Task.WhenAll(deliveries);
    }

    private async Task SendWebhookAsync(
        NotificationConfig config,
        BaseNotificationData notificationData)
    {
        try
        {
            await new WebhookNotifier(_httpClient, config)
                .SendAsync(notificationData);
        }
        catch (Exception exception)
        {
            logger.LogWarning(
                exception,
                "Webhook notification event {Event} failed.",
                notificationData.Event);
        }
    }

    private async Task EmitNativeAsync(BaseNotificationData notificationData)
    {
        var response = await callbacks.InvokeAsync(
            "notification.emit",
            JObject.FromObject(new
            {
                eventCode = notificationData.Event,
                result = notificationData.Result.ToString(),
                message = notificationData.Message ?? "",
            }),
            sessionToken,
            cancellationToken);
        if (response?.Value<bool?>("acknowledged") != true)
            throw new InvalidDataException(
                "notification.emit did not return acknowledged=true.");
    }

    private NotificationConfig ReadConfig()
    {
        lock (_lock)
            return ReadConfigLocked();
    }

    private NotificationConfig ReadConfigLocked()
    {
        var notification = LoadRoot()["notificationConfig"];
        return notification?.Deserialize<NotificationConfig>(ConfigJson.Options)
            ?? new NotificationConfig();
    }

    private static object Describe(NotificationConfig config)
    {
        var selected = NotificationEventSubscriptionHelper.ParseEventCodes(
                config.NotificationEventSubscribe)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        return new
        {
            jsNotificationEnabled = config.JsNotificationEnabled,
            macOSNotificationEnabled = config.WindowsUwpNotificationEnabled,
            notificationEventSubscribe = config.NotificationEventSubscribe,
            events = NotificationEvent.GetAll().Select(notificationEvent => new
            {
                code = notificationEvent.Code,
                displayName = notificationEvent.Msg,
                selected = selected.Contains(notificationEvent.Code),
            }),
            webhookEnabled = config.WebhookEnabled,
            webhookEndpoint = config.WebhookEndpoint,
            webhookSendTo = config.WebhookSendTo,
        };
    }

    private static string NormalizeKnownEventCodes(string eventSubscribe)
    {
        var known = NotificationEvent.GetAll()
            .Select(notificationEvent => notificationEvent.Code)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var requested = NotificationEventSubscriptionHelper.ParseEventCodes(
            eventSubscribe);
        var unknown = requested.FirstOrDefault(code => !known.Contains(code));
        if (unknown is not null)
            throw new ArgumentException($"Unknown notification event code: {unknown}");
        return NotificationEventSubscriptionHelper.NormalizeEventCodes(requested);
    }

    private JsonObject LoadRoot()
    {
        var path = Path.Combine(layout.UserPath, "config.json");
        if (!File.Exists(path))
            return [];
        return JsonNode.Parse(
            File.ReadAllText(path),
            documentOptions: new JsonDocumentOptions
            {
                AllowTrailingCommas = true,
                CommentHandling = JsonCommentHandling.Skip,
            }) as JsonObject
            ?? throw new InvalidDataException(
                "User/config.json root must be an object.");
    }

    private void SaveRoot(JsonObject root)
    {
        Directory.CreateDirectory(layout.UserPath);
        var path = Path.Combine(layout.UserPath, "config.json");
        var temporaryPath = $"{path}.{Guid.NewGuid():N}.tmp";
        File.WriteAllText(temporaryPath, root.ToJsonString(ConfigJson.Options));
        File.Move(temporaryPath, path, true);
    }

    private static bool RequiredBoolean(JObject settings, string name) =>
        settings.Value<bool?>(name)
        ?? throw new ArgumentException($"{name} is required.");
}
