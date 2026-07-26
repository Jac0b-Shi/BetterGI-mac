using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Script.Dependence;
using BetterGenshinImpact.Service.Notification;
using BetterGenshinImpact.Service.Notification.Model;
using BetterGenshinImpact.Service.Notification.Model.Enum;
using BetterGenshinImpact.Service.Notifier;
using BetterGenshinImpact.Service.Notifier.Interface;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace BetterGenshinImpact.Core.Host.Runtime;

public sealed class NotificationSettingsCatalog : IDisposable
{
    private static readonly ChannelDescriptor[] ChannelDescriptors =
    [
        new(
            "webhook",
            "Webhook",
            "向兼容 BetterGI 通知载荷的 HTTP 端点发送事件",
            "webhookEnabled",
            [
                new("webhookEndpoint", "Webhook 地址", "string",
                    "https://example.com/webhook"),
                new("webhookSendTo", "发送目标", "string", "可选"),
            ]),
        new(
            "websocket",
            "WebSocket",
            "通过 WebSocket 发送 BetterGI 通知事件",
            "webSocketNotificationEnabled",
            [
                new("webSocketEndpoint", "WebSocket 地址", "string",
                    "wss://example.com/notifications"),
            ]),
        new(
            "feishu",
            "飞书",
            "通过飞书 Webhook 或应用凭据发送通知",
            "feishuNotificationEnabled",
            [
                new("feishuWebhookUrl", "Webhook 地址", "string"),
                new("feishuAppId", "App ID", "string"),
                new("feishuAppSecret", "App Secret", "secret"),
            ]),
        new(
            "oneBot",
            "OneBot",
            "通过 OneBot HTTP 接口发送私聊或群通知",
            "oneBotNotificationEnabled",
            [
                new("oneBotEndpoint", "请求地址", "string"),
                new("oneBotUserId", "用户 ID", "string"),
                new("oneBotGroupId", "群 ID", "string"),
                new("oneBotToken", "Token", "secret"),
            ]),
        new(
            "workWeixin",
            "企业微信",
            "通过企业微信群机器人 Webhook 发送通知",
            "workweixinNotificationEnabled",
            [
                new("workweixinWebhookUrl", "Webhook 地址", "string"),
            ]),
        new(
            "email",
            "邮件",
            "通过 SMTP 发送 BetterGI 通知",
            "emailNotificationEnabled",
            [
                new("smtpServer", "SMTP 服务器", "string"),
                new("smtpPort", "SMTP 端口", "integer"),
                new("smtpUsername", "SMTP 用户名", "string"),
                new("smtpPassword", "SMTP 密码", "secret"),
                new("fromEmail", "发件地址", "string"),
                new("fromName", "发件人名称", "string"),
                new("toEmail", "收件地址", "string"),
            ]),
        new(
            "bark",
            "Bark",
            "向 Bark 设备发送移动推送",
            "barkNotificationEnabled",
            [
                new("barkApiEndpoint", "API 地址", "string"),
                new("barkDeviceKeys", "设备 Key", "secret"),
                new("barkLevel", "中断级别", "select", Options:
                    ["critical", "active", "timeSensitive", "passive"]),
                new("barkSound", "通知声音", "string"),
                new("barkIcon", "图标 URL", "string"),
                new("barkGroup", "通知分组", "string"),
                new("barkIsArchive", "保存推送", "select", Options: ["1", "0"]),
                new("barkCiphertext", "加密密文", "secret"),
            ]),
        new(
            "telegram",
            "Telegram",
            "通过 Telegram Bot API 发送通知",
            "telegramNotificationEnabled",
            [
                new("telegramBotToken", "Bot Token", "secret"),
                new("telegramChatId", "Chat ID", "string"),
                new("telegramApiBaseUrl", "API 基础地址", "string"),
                new("telegramProxyEnabled", "启用代理", "boolean"),
                new("telegramProxyUrl", "代理地址", "string"),
            ]),
        new(
            "xxtui",
            "xxtui 信息推送",
            "通过 xxtui.com 分发通知",
            "xxtuiNotificationEnabled",
            [
                new("xxtuiApiKey", "API Key", "secret"),
                new("xxtuiFrom", "消息来源", "string"),
                new("xxtuiChannels", "推送渠道", "string"),
            ]),
        new(
            "dingDing",
            "钉钉",
            "通过钉钉群机器人 Webhook 发送通知",
            "dingDingwebhookNotificationEnabled",
            [
                new("dingdingWebhookUrl", "Webhook 地址", "string"),
                new("dingDingSecret", "加签密钥", "secret"),
            ]),
        new(
            "discord",
            "Discord",
            "通过 Discord Webhook 发送通知",
            "discordWebhookNotificationEnabled",
            [
                new("discordWebhookUrl", "Webhook 地址", "string"),
                new("discordWebhookUsername", "用户名", "string"),
                new("discordWebhookAvatarUrl", "头像地址", "string"),
                new("discordWebhookImageEncoder", "图片格式", "select",
                    Options: ["Jpeg", "Png", "WebP"]),
            ]),
        new(
            "serverChan",
            "ServerChan",
            "通过 ServerChan 发送通知",
            "serverChanNotificationEnabled",
            [
                new("serverChanSendKey", "SendKey", "secret"),
            ]),
        new(
            "meow",
            "MeoW",
            "通过 MeoW 推送服务发送通知",
            "meowNotificationEnabled",
            [
                new("meowNickname", "昵称", "string"),
                new("meowTitle", "标题", "string"),
            ]),
    ];

    private readonly object _lock = new();
    private readonly RuntimeLayout _layout;
    private readonly NotificationService _notificationService;
    private MacScriptHostServices? _scriptHostServices;

    public NotificationSettingsCatalog(
        RuntimeLayout layout,
        PlatformCallbackChannel callbacks,
        string sessionToken,
        CancellationToken cancellationToken,
        Func<Image<Rgb24>?> screenshotProvider,
        ILogger<NotificationSettingsCatalog> logger)
    {
        _layout = layout;
        var manager = new NotifierManager(logger);
        _notificationService = new NotificationService(
            manager,
            ReadConfig,
            () => new MacNativeNotificationNotifier(
                callbacks,
                sessionToken,
                cancellationToken),
            screenshotProvider,
            logger);
        _notificationService.StartAsync(cancellationToken)
            .GetAwaiter()
            .GetResult();
    }

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
        var includeScreenShot = RequiredBoolean(settings, "includeScreenShot");
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
            notification["includeScreenShot"] = includeScreenShot;
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
            _notificationService.RefreshNotifiers();
            return Describe(config);
        }
    }

    public object SaveChannel(
        string channelId,
        JObject values)
    {
        var channel = ChannelDescriptors.FirstOrDefault(
            item => string.Equals(
                item.Id,
                channelId,
                StringComparison.Ordinal))
            ?? throw new KeyNotFoundException(
                $"Unknown notification channel: {channelId}");
        var fields = channel.Fields
            .Append(new FieldDescriptor(
                channel.EnabledField,
                "启用",
                "boolean"))
            .ToDictionary(field => field.Id, StringComparer.Ordinal);
        var unknown = values.Properties()
            .FirstOrDefault(property => !fields.ContainsKey(property.Name));
        if (unknown is not null)
            throw new KeyNotFoundException(
                $"Unknown notification field: {channelId}.{unknown.Name}");

        lock (_lock)
        {
            var root = LoadRoot();
            var notification = root["notificationConfig"] as JsonObject ?? [];
            foreach (var property in values.Properties())
            {
                notification[property.Name] = NormalizeFieldValue(
                    fields[property.Name],
                    property.Value);
            }
            var config = notification.Deserialize<NotificationConfig>(
                    ConfigJson.Options)
                ?? new NotificationConfig();
            root["notificationConfig"] = notification;
            SaveRoot(root);
            _notificationService.RefreshNotifiers();
            return Describe(config);
        }
    }

    public async Task<object> TestAsync(string channel)
    {
        var config = ReadConfig();
        var result = channel switch
        {
            "native" when config.WindowsUwpNotificationEnabled =>
                await _notificationService
                    .TestNotifierAsync<MacNativeNotificationNotifier>(),
            "webhook" => await _notificationService
                .TestNotifierAsync<WebhookNotifier>(),
            "websocket" => await _notificationService
                .TestNotifierAsync<WebSocketNotifier>(),
            "feishu" => await _notificationService
                .TestNotifierAsync<FeishuNotifier>(),
            "oneBot" => await _notificationService
                .TestNotifierAsync<OneBotNotifier>(),
            "workWeixin" => await _notificationService
                .TestNotifierAsync<WorkWeixinNotifier>(),
            "email" => await _notificationService
                .TestNotifierAsync<EmailNotifier>(),
            "bark" => await _notificationService
                .TestNotifierAsync<BarkNotifier>(),
            "telegram" => await _notificationService
                .TestNotifierAsync<TelegramNotifier>(),
            "xxtui" => await _notificationService
                .TestNotifierAsync<XxtuiNotifier>(),
            "dingDing" => await _notificationService
                .TestNotifierAsync<DingDingWebhook>(),
            "discord" => await _notificationService
                .TestNotifierAsync<DiscordWebhookNotifier>(),
            "serverChan" => await _notificationService
                .TestNotifierAsync<ServerChanNotifier>(),
            "meow" => await _notificationService
                .TestNotifierAsync<MeowNotifier>(),
            "native" => throw new InvalidOperationException(
                "macOS 通知尚未启用。"),
            _ => throw new ArgumentException(
                $"Unknown notification channel: {channel}"),
        };
        if (!result.IsSuccess)
            throw new InvalidOperationException(result.Message);
        return new { channel, sent = true };
    }

    public void Dispose()
    {
        _notificationService.StopAsync(CancellationToken.None)
            .GetAwaiter()
            .GetResult();
        _notificationService.Dispose();
        GC.SuppressFinalize(this);
    }

    private void EmitScriptNotification(ScriptNotificationKind kind, string message)
    {
        var eventCode = kind == ScriptNotificationKind.Error
            ? NotificationEvent.JsError.Code
            : NotificationEvent.JsCustom.Code;
        _notificationService.NotifyAllNotifiers(new BaseNotificationData
        {
            Event = eventCode,
            Result = kind == ScriptNotificationKind.Error
                ? NotificationEventResult.Fail
                : NotificationEventResult.Success,
            Message = message,
        });
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
            includeScreenShot = config.IncludeScreenShot,
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
            channels = DescribeChannels(config),
        };
    }

    private static object[] DescribeChannels(NotificationConfig config)
    {
        var values = JsonSerializer.SerializeToNode(
                config,
                ConfigJson.Options) as JsonObject
            ?? [];
        return ChannelDescriptors.Select(channel => new
        {
            id = channel.Id,
            title = channel.Title,
            subtitle = channel.Subtitle,
            enabledField = channel.EnabledField,
            enabled = ReadBoolean(values, channel.EnabledField),
            fields = channel.Fields.Select(field => new
            {
                id = field.Id,
                label = field.Label,
                kind = field.Kind,
                placeholder = field.Placeholder ?? "",
                options = field.Options ?? [],
                value = ReadFieldValue(values, field),
            }).ToArray(),
        }).Cast<object>().ToArray();
    }

    private static object ReadFieldValue(
        JsonObject values,
        FieldDescriptor field) =>
        field.Kind switch
        {
            "boolean" => ReadBoolean(values, field.Id),
            "integer" => values[field.Id]?.GetValue<int>() ?? 0,
            _ => values[field.Id]?.GetValue<string>() ?? "",
        };

    private static bool ReadBoolean(JsonObject values, string id) =>
        values[id]?.GetValue<bool>() ?? false;

    private static JsonNode NormalizeFieldValue(
        FieldDescriptor field,
        JToken value)
    {
        return field.Kind switch
        {
            "boolean" when value.Type == JTokenType.Boolean =>
                JsonValue.Create(value.Value<bool>())!,
            "integer" when value.Type == JTokenType.Integer =>
                JsonValue.Create(value.Value<int>())!,
            "string" or "secret" when value.Type == JTokenType.String =>
                JsonValue.Create(value.Value<string>() ?? "")!,
            "select" when value.Type == JTokenType.String &&
                          field.Options?.Contains(
                              value.Value<string>() ?? "",
                              StringComparer.Ordinal) == true =>
                JsonValue.Create(value.Value<string>() ?? "")!,
            _ => throw new ArgumentException(
                $"Invalid value for notification field {field.Id}."),
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
        var path = Path.Combine(_layout.UserPath, "config.json");
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
        Directory.CreateDirectory(_layout.UserPath);
        var path = Path.Combine(_layout.UserPath, "config.json");
        var temporaryPath = $"{path}.{Guid.NewGuid():N}.tmp";
        File.WriteAllText(temporaryPath, root.ToJsonString(ConfigJson.Options));
        File.Move(temporaryPath, path, true);
    }

    private static bool RequiredBoolean(JObject settings, string name) =>
        settings.Value<bool?>(name)
        ?? throw new ArgumentException($"{name} is required.");

    private sealed record ChannelDescriptor(
        string Id,
        string Title,
        string Subtitle,
        string EnabledField,
        FieldDescriptor[] Fields);

    private sealed record FieldDescriptor(
        string Id,
        string Label,
        string Kind,
        string? Placeholder = null,
        string[]? Options = null);

    private sealed class MacNativeNotificationNotifier(
        PlatformCallbackChannel callbacks,
        string sessionToken,
        CancellationToken cancellationToken) : INotifier
    {
        public string Name => "macOS 通知";

        public async Task SendAsync(BaseNotificationData data)
        {
            var response = await callbacks.InvokeAsync(
                "notification.emit",
                JObject.FromObject(new
                {
                    eventCode = data.Event,
                    result = data.Result.ToString(),
                    message = data.Message ?? "",
                }),
                sessionToken,
                cancellationToken);
            if (response?.Value<bool?>("acknowledged") != true)
                throw new InvalidDataException(
                    "notification.emit did not return acknowledged=true.");
        }
    }
}
