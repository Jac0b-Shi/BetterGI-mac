using BetterGenshinImpact.Core.Host;
using BetterGenshinImpact.Core.Host.Protocol;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Recorder;
using BetterGenshinImpact.Core.Recorder.Model;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.Service.Notification;
using BetterGenshinImpact.Verification.Framework;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using System.Net;
using System.Net.Sockets;
using System.Runtime.Versioning;
using System.Text;

namespace BetterGenshinImpact.Core.Host.Fast.Verification;

public sealed class RuntimeSettingsSuite : IVerificationSuite
{
    public string Name => "runtime-settings";

    [SupportedOSPlatform("macos")]
    public async Task RunAsync(VerificationContext context, CancellationToken cancellationToken)
    {
        var root = Path.Combine(Path.GetTempPath(), $"bettergi-runtime-settings-{Guid.NewGuid():N}");
        try
        {
            var layout = new RuntimeLayout(root);
            layout.EnsureCreated();
            var configPath = Path.Combine(layout.UserPath, "config.json");
            await File.WriteAllTextAsync(configPath, """
                {
                  "preserved": { "value": 42 },
                  "macroConfig": {
                    "fPressHoldToContinuationEnabled": false,
                    "fFireInterval": 100,
                    "spacePressHoldToContinuationEnabled": false,
                    "spaceFireInterval": 100
                  },
                  "keyBindingsConfig": {
                    "moveForward": 71,
                    "normalAttack": 5,
                    "pickUpOrInteract": 71,
                    "jump": 74
                  },
                  "notificationConfig": {
                    "jsNotificationEnabled": false,
                    "windowsUwpNotificationEnabled": false,
                    "notificationEventSubscribe": "js.custom",
                    "webhookEnabled": false,
                    "webhookEndpoint": "",
                    "webhookSendTo": ""
                  },
                  "hotKeyConfig": {
                    "bgiEnabledHotkey": "F11",
                    "bgiEnabledHotkeyType": "GlobalRegister",
                    "autoPickEnabledHotkey": "F7",
                    "autoPickEnabledHotkeyType": "KeyboardMonitor",
                    "autoSkipEnabledHotkey": "",
                    "autoSkipEnabledHotkeyType": "KeyboardMonitor"
                  }
                }
                """, cancellationToken);

            using var loggerFactory = LoggerFactory.Create(_ => { });
            var macroCatalog = new MacroSettingsCatalog(layout);
            var keyResolver = new GameActionKeyResolver(layout);
            var moveForward = keyResolver.Resolve(
                BetterGenshinImpact.Core.Simulator.Extensions.GIActions.MoveForward);
            var normalAttack = keyResolver.Resolve(
                BetterGenshinImpact.Core.Simulator.Extensions.GIActions.NormalAttack);
            var openMap = keyResolver.Resolve(
                BetterGenshinImpact.Core.Simulator.Extensions.GIActions.OpenMap);
            context.Require(
                moveForward.WindowsVirtualKey == 71 &&
                moveForward.MouseButton is null &&
                normalAttack.WindowsVirtualKey is null &&
                normalAttack.MouseButton == "side1" &&
                openMap.WindowsVirtualKey == 0x4D,
                "GameActionKeyResolver did not preserve configured keys, mouse buttons or upstream defaults.");

            _ = macroCatalog.Save(JObject.FromObject(new
            {
                fPressHoldToContinuationEnabled = true,
                fFireInterval = 80,
                spacePressHoldToContinuationEnabled = true,
                spaceFireInterval = 120,
            }));
            var repeatedKeys = new List<int>();
            using (var auxiliaryControls = new AuxiliaryControlCoordinator(
                       macroCatalog,
                       (windowsVirtualKey, token) =>
                       {
                           token.ThrowIfCancellationRequested();
                           lock (repeatedKeys)
                               repeatedKeys.Add(windowsVirtualKey);
                       },
                       cancellationToken,
                       loggerFactory.CreateLogger<AuxiliaryControlCoordinator>()))
            {
                auxiliaryControls.Start();
                var armed = JObject.FromObject(
                    auxiliaryControls.HandleKeyEdge(
                        AuxiliaryControlCoordinator.PickUpOrInteractControl,
                        true));
                var held = JObject.FromObject(
                    auxiliaryControls.HandleKeyEdge(
                        AuxiliaryControlCoordinator.PickUpOrInteractControl,
                        true));
                await Task.Delay(150, cancellationToken);
                lock (repeatedKeys)
                {
                    context.Require(
                        repeatedKeys.Count == 0,
                        "Auxiliary controls emitted input before the upstream hold threshold.");
                }
                for (var retry = 0; retry < 50; retry++)
                {
                    lock (repeatedKeys)
                    {
                        if (repeatedKeys.Count > 0)
                            break;
                    }
                    await Task.Delay(20, cancellationToken);
                }
                int[] emittedKeys;
                lock (repeatedKeys)
                    emittedKeys = repeatedKeys.ToArray();
                context.Require(
                    armed.Value<string>("state") == "armed" &&
                    held.Value<string>("state") == "held" &&
                    emittedKeys.Length > 0 &&
                    emittedKeys.All(key => key == 71),
                    "Auxiliary controls did not preserve the upstream hold threshold, key binding or key-down deduplication.");
                _ = auxiliaryControls.HandleKeyEdge(
                    AuxiliaryControlCoordinator.PickUpOrInteractControl,
                    false);
                await Task.Delay(120, cancellationToken);
                lock (repeatedKeys)
                {
                    context.Require(
                        repeatedKeys.Count == emittedKeys.Length,
                        "Auxiliary controls continued after the physical key-up edge.");
                }
                await auxiliaryControls.StopAsync();
                var stopped = JObject.FromObject(
                    auxiliaryControls.HandleKeyEdge(
                        AuxiliaryControlCoordinator.PickUpOrInteractControl,
                        true));
                context.Require(
                    stopped.Value<string>("state") == "stopped",
                    "Auxiliary controls accepted a late key-down edge after runtime stop.");
            }

            var scriptHostServices = new MacScriptHostServices(loggerFactory);
            var notificationCatalog = new NotificationSettingsCatalog(
                layout, new PlatformCallbackChannel(), "verification", cancellationToken,
                loggerFactory.CreateLogger<NotificationSettingsCatalog>());
            notificationCatalog.AttachScriptHostServices(scriptHostServices);
            _ = notificationCatalog.Save(JObject.FromObject(new
            {
                jsNotificationEnabled = true,
                macOSNotificationEnabled = true,
                notificationEventSubscribe = "js.error,js.custom,JS.ERROR",
                webhookEnabled = false,
                webhookEndpoint = "",
                webhookSendTo = "verification",
            }));
            var notificationSettings = JObject.FromObject(notificationCatalog.Get());
            var notificationEvents = (JArray)notificationSettings["events"]!;
            context.Require(
                notificationSettings.Value<string>("notificationEventSubscribe") ==
                    "js.error,js.custom" &&
                notificationEvents.Any(item =>
                    item.Value<string>("code") == "js.error" &&
                    item.Value<bool>("selected")) &&
                notificationEvents.Any(item =>
                    item.Value<string>("code") == "domain.reward" &&
                    !item.Value<bool>("selected")) &&
                NotificationEventSubscriptionHelper.ShouldSendNotification(
                    "js.error,js.custom", "JS.CUSTOM") &&
                !NotificationEventSubscriptionHelper.ShouldSendNotification(
                    "js.error,js.custom", "domain.end"),
                "Notification settings did not preserve the upstream event subscription contract.");
            context.Require(
                Throws<ArgumentException>(() => notificationCatalog.Save(
                    JObject.FromObject(new
                    {
                        jsNotificationEnabled = true,
                        macOSNotificationEnabled = true,
                        notificationEventSubscribe = "unknown.event",
                        webhookEnabled = false,
                        webhookEndpoint = "",
                        webhookSendTo = "",
                    }))),
                "Notification settings accepted an unknown event code.");
            using var webhookListener = new TcpListener(IPAddress.Loopback, 0);
            webhookListener.Start();
            var webhookEndpoint =
                $"http://127.0.0.1:{((IPEndPoint)webhookListener.LocalEndpoint).Port}/notify";
            var webhookRequestTask = ReadHttpRequestBodyAsync(
                webhookListener, cancellationToken);
            _ = notificationCatalog.Save(JObject.FromObject(new
            {
                jsNotificationEnabled = true,
                macOSNotificationEnabled = true,
                notificationEventSubscribe = "js.error,js.custom",
                webhookEnabled = true,
                webhookEndpoint,
                webhookSendTo = "verification",
            }));
            _ = await notificationCatalog.TestAsync("webhook");
            var webhookPayload = JObject.Parse(await webhookRequestTask);
            context.Require(
                webhookPayload.Value<string>("send_to") == "verification" &&
                webhookPayload.Value<string>("event") == "notify.test" &&
                webhookPayload.Value<int>("result") == 0 &&
                webhookPayload.Value<string>("message") ==
                    "这是一条 BetterGI 测试通知。",
                $"The extracted upstream Webhook notifier sent an unexpected test payload: {webhookPayload}");

            var hotKeyUpdates = new List<(string Id, string HotKey)>();
            var hotKeyCatalog = new HotKeySettingsCatalog(layout);
            var quickTeleportPlatform = new MacQuickTeleportRuntimePlatform(
                layout, new PlatformCallbackChannel(), "verification",
                cancellationToken);
            hotKeyCatalog.AttachUpdated((id, hotKey) =>
            {
                hotKeyUpdates.Add((id, hotKey));
                if (id == "QuickTeleportTickHotkey")
                    quickTeleportPlatform.UpdateTickHotkey(hotKey);
            });
            _ = hotKeyCatalog.Save(JObject.FromObject(new
            {
                id = "AutoSkipEnabledHotkey",
                hotKey = "F7",
                hotKeyType = "KeyboardMonitor",
            }));
            _ = hotKeyCatalog.Save(JObject.FromObject(new
            {
                id = "QuickTeleportTickHotkey",
                hotKey = "F6",
                hotKeyType = "KeyboardMonitor",
            }));
            _ = hotKeyCatalog.Save(JObject.FromObject(new
            {
                id = "AutoPickEnabledHotkey",
                hotKey = "F6",
                hotKeyType = "KeyboardMonitor",
            }));
            var hotKeys = JArray.FromObject(hotKeyCatalog.List());
            context.Require(
                hotKeys.Count == 20 &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "AutoPickEnabledHotkey")
                    .Value<string>("hotKey") == "F6" &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "AutoSkipEnabledHotkey")
                    .Value<string>("hotKey") == "F7" &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "QuickTeleportTickHotkey")
                    .Value<string>("hotKey") == "" &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "QuickTeleportTickHotkey")
                    .Value<bool>("dispatchOnPress") == false &&
                hotKeyUpdates.Contains(("QuickTeleportTickHotkey", "F6")) &&
                hotKeyUpdates.Contains(("QuickTeleportTickHotkey", "")) &&
                quickTeleportPlatform.TickHotkey == "",
                "Hotkey settings did not preserve the upstream catalog, duplicate removal or hold observation contract.");
            context.Require(
                Throws<ArgumentException>(
                () => hotKeyCatalog.Save(JObject.FromObject(new
                {
                    id = "AutoPickEnabledHotkey",
                    hotKey = "Ctrl + F7",
                    hotKeyType = "KeyboardMonitor",
                }))),
                "Hotkey settings accepted a modifier combination that the macOS monitor cannot parse.");
            context.Require(
                Throws<ArgumentException>(
                () => hotKeyCatalog.Save(JObject.FromObject(new
                {
                    id = "BgiEnabledHotkey",
                    hotKey = "A",
                    hotKeyType = "GlobalRegister",
                }))),
                "Hotkey settings accepted an unmodified global character key.");

            var persisted = JObject.Parse(await File.ReadAllTextAsync(configPath, cancellationToken));
            context.Require(
                persisted["preserved"]?.Value<int>("value") == 42 &&
                persisted["macroConfig"]?.Value<int>("fFireInterval") == 80 &&
                persisted["macroConfig"]?.Value<int>("spaceFireInterval") == 120 &&
                persisted["notificationConfig"]?.Value<bool>("jsNotificationEnabled") == true &&
                persisted["notificationConfig"]?.Value<bool>("windowsUwpNotificationEnabled") == true &&
                persisted["notificationConfig"]?.Value<string>("notificationEventSubscribe") ==
                    "js.error,js.custom" &&
                persisted["notificationConfig"]?.Value<string>("webhookSendTo") ==
                    "verification" &&
                persisted["notificationConfig"]?.Value<bool>("webhookEnabled") ==
                    true &&
                persisted["hotKeyConfig"]?.Value<string>("autoPickEnabledHotkey") == "F6" &&
                persisted["hotKeyConfig"]?.Value<string>("autoSkipEnabledHotkey") == "F7" &&
                persisted["hotKeyConfig"]?.Value<string>("quickTeleportTickHotkey") == "" &&
                scriptHostServices.JsNotificationEnabled,
                "Runtime settings did not preserve unrelated config or update Core notification state.");

            var script = KeyMouseScriptBuilder.Build(
            [
                new MacroEvent { Type = MacroEventType.MouseMoveBy, MouseX = 2, MouseY = 3, Time = 10 },
                new MacroEvent { Type = MacroEventType.MouseMoveBy, MouseX = 4, MouseY = 5, Time = 25 },
                new MacroEvent { Type = MacroEventType.KeyDown, KeyCode = 70, Time = 30 },
                new MacroEvent { Type = MacroEventType.KeyUp, KeyCode = 70, Time = 40 },
                new MacroEvent { Type = MacroEventType.MouseMoveTo, MouseX = 90, MouseY = 80, Time = -1 },
            ],
            new KeyMouseScriptInfo { Width = 1920, Height = 1080, RecordDpi = 2 });
            context.Require(
                script.MacroEvents.Count == 3 &&
                script.MacroEvents[0].Type == MacroEventType.MouseMoveBy &&
                script.MacroEvents[0].MouseX == 6 &&
                script.MacroEvents[0].MouseY == 8 &&
                script.MacroEvents.All(macroEvent => macroEvent.Time >= 0),
                "KeyMouseScriptBuilder drifted from upstream ordering, filtering or merge semantics.");

            await VerifyRpcSurfaceAsync(
                context, layout, loggerFactory, scriptHostServices,
                notificationCatalog, cancellationToken);
        }
        finally
        {
            if (Directory.Exists(root))
                Directory.Delete(root, recursive: true);
        }
    }

    [SupportedOSPlatform("macos")]
    private static async Task VerifyRpcSurfaceAsync(
        VerificationContext context,
        RuntimeLayout layout,
        ILoggerFactory loggerFactory,
        MacScriptHostServices scriptHostServices,
        NotificationSettingsCatalog notificationCatalog,
        CancellationToken cancellationToken)
    {
        var socketPath = Path.Combine(
            "/tmp", $"bgi-rpc-{Guid.NewGuid():N}"[..24] + ".sock");
        const string sessionToken = "runtime-settings-verification";
        using var serverCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var server = new CoreRpcServer(
            socketPath,
            sessionToken,
            layout,
            new NativeDependencyStatus("8.0", "Arm64", "4.13.0", true));
        server.AttachScriptHostServices(scriptHostServices);
        server.AttachNotificationSettings(notificationCatalog);
        server.AttachKeyMouseScriptCoordinator(new KeyMouseScriptCoordinator(
            layout,
            loggerFactory.CreateLogger<KeyMouseScriptCoordinator>(),
            serverCancellation.Token));
        using var auxiliaryControls = new AuxiliaryControlCoordinator(
            server.MacroSettings,
            (_, token) => token.ThrowIfCancellationRequested(),
            serverCancellation.Token,
            loggerFactory.CreateLogger<AuxiliaryControlCoordinator>());
        server.MacroSettings.AttachUpdated(auxiliaryControls.ApplySettings);
        server.AttachAuxiliaryControlCoordinator(auxiliaryControls);
        auxiliaryControls.Start();
        var serverTask = server.RunAsync(serverCancellation.Token);

        try
        {
            for (var retry = 0; retry < 100 && !File.Exists(socketPath); retry++)
                await Task.Delay(10, cancellationToken);
            context.Require(File.Exists(socketPath), "Core RPC socket was not created.");

            using var socket = new Socket(
                AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
            await socket.ConnectAsync(new UnixDomainSocketEndPoint(socketPath), cancellationToken);
            await using var connection = new FramedJsonConnection(socket);

            var macroSave = await ExchangeAsync(
                connection, "macro-save", "macro.settings.save", sessionToken,
                JObject.FromObject(new
                {
                    settings = new
                    {
                        fPressHoldToContinuationEnabled = true,
                        fFireInterval = 70,
                        spacePressHoldToContinuationEnabled = false,
                        spaceFireInterval = 130,
                    }
                }), cancellationToken);
            var macroResult = JObject.FromObject(macroSave.Result!);
            context.Require(
                macroSave.Error is null &&
                macroResult.Value<int>("fFireInterval") == 70 &&
                macroResult.Value<int>("spaceFireInterval") == 130 &&
                macroResult.Value<int>("pickUpOrInteractKeyCode") == 71 &&
                macroResult.Value<int>("jumpKeyCode") == 74,
                macroSave.Error?.Message ?? "macro.settings.save returned an invalid result.");

            var macroKeyDown = await ExchangeAsync(
                connection, "macro-key-down", "macro.keyEdge", sessionToken,
                JObject.FromObject(new
                {
                    control = AuxiliaryControlCoordinator.PickUpOrInteractControl,
                    isDown = true,
                }), cancellationToken);
            var macroKeyUp = await ExchangeAsync(
                connection, "macro-key-up", "macro.keyEdge", sessionToken,
                JObject.FromObject(new
                {
                    control = AuxiliaryControlCoordinator.PickUpOrInteractControl,
                    isDown = false,
                }), cancellationToken);
            context.Require(
                macroKeyDown.Error is null &&
                JObject.FromObject(macroKeyDown.Result!).Value<string>("state") ==
                    "armed" &&
                macroKeyUp.Error is null &&
                JObject.FromObject(macroKeyUp.Result!).Value<string>("state") ==
                    "released",
                macroKeyDown.Error?.Message ??
                macroKeyUp.Error?.Message ??
                "macro.keyEdge did not preserve the Core-owned press lifecycle.");

            var notificationGet = await ExchangeAsync(
                connection, "notification-get", "notification.settings.get",
                sessionToken, null, cancellationToken);
            var notificationResult = JObject.FromObject(notificationGet.Result!);
            context.Require(
                notificationGet.Error is null &&
                notificationResult.Value<bool>("jsNotificationEnabled") &&
                notificationResult.Value<bool>("macOSNotificationEnabled") &&
                notificationResult.Value<string>("notificationEventSubscribe") ==
                    "js.error,js.custom" &&
                notificationResult.Value<bool>("webhookEnabled") &&
                ((JArray)notificationResult["events"]!).Count > 10,
                notificationGet.Error?.Message ?? "notification.settings.get returned an invalid result.");

            var hotKeyList = await ExchangeAsync(
                connection, "hotkey-list", "hotKey.settings.list",
                sessionToken, null, cancellationToken);
            var hotKeyListResult = JArray.FromObject(hotKeyList.Result!);
            context.Require(
                hotKeyList.Error is null &&
                hotKeyListResult.Any(item =>
                    item.Value<string>("id") == "BgiEnabledHotkey" &&
                    item.Value<string>("hotKey") == "F11"),
                hotKeyList.Error?.Message ??
                    "hotKey.settings.list did not return the persisted upstream binding.");

            var hotKeySave = await ExchangeAsync(
                connection, "hotkey-save", "hotKey.settings.save",
                sessionToken, JObject.FromObject(new
                {
                    binding = new
                    {
                        id = "BgiEnabledHotkey",
                        hotKey = "Ctrl + Shift + F10",
                        hotKeyType = "GlobalRegister",
                    }
                }), cancellationToken);
            var hotKeySaveResult = JArray.FromObject(hotKeySave.Result!);
            context.Require(
                hotKeySave.Error is null &&
                hotKeySaveResult.Any(item =>
                    item.Value<string>("id") == "BgiEnabledHotkey" &&
                    item.Value<string>("hotKey") == "Ctrl + Shift + F10" &&
                    item.Value<string>("executionOwner") == "swift"),
                hotKeySave.Error?.Message ??
                    "hotKey.settings.save did not preserve the platform-owned runtime binding.");

            RunnerContext.Instance.IsSuspend = false;
            var suspend = await ExchangeAsync(
                connection, "hotkey-suspend", "hotKey.invoke",
                sessionToken, JObject.FromObject(new
                {
                    id = "SuspendHotkey",
                }), cancellationToken);
            var suspendResult = JObject.FromObject(suspend.Result!);
            context.Require(
                suspend.Error is null &&
                suspendResult.Value<string>("state") == "paused" &&
                RunnerContext.Instance.IsSuspend,
                suspend.Error?.Message ??
                    "hotKey.invoke did not toggle the shared RunnerContext suspension state.");
            RunnerContext.Instance.IsSuspend = false;

            var saveRecording = await ExchangeAsync(
                connection, "recording-save", "keyMouse.saveRecording", sessionToken,
                JObject.FromObject(new
                {
                    events = new object[]
                    {
                        new { type = 0, keyCode = 70, mouseX = 0, mouseY = 0, time = 10 },
                        new { type = 1, keyCode = 70, mouseX = 0, mouseY = 0, time = 40 },
                    },
                    info = new { x = 0, y = 0, width = 1920, height = 1080, recordDpi = 2 },
                }), cancellationToken);
            var saved = JObject.FromObject(saveRecording.Result!);
            var scriptId = saved.Value<string>("id");
            context.Require(
                saveRecording.Error is null && !string.IsNullOrWhiteSpace(scriptId) &&
                saved.Value<int>("eventCount") == 2,
                saveRecording.Error?.Message ?? "keyMouse.saveRecording returned an invalid result.");

            var list = await ExchangeAsync(
                connection, "recording-list", "keyMouse.list", sessionToken,
                null, cancellationToken);
            var listed = JArray.FromObject(list.Result!);
            context.Require(
                list.Error is null &&
                listed.Any(item => item.Value<string>("id") == scriptId),
                list.Error?.Message ?? "keyMouse.list did not return the saved recording.");

            var rename = await ExchangeAsync(
                connection, "recording-rename", "keyMouse.rename", sessionToken,
                JObject.FromObject(new { id = scriptId, name = "RPC 验证" }),
                cancellationToken);
            var renamed = JObject.FromObject(rename.Result!);
            var renamedId = renamed.Value<string>("id");
            context.Require(
                rename.Error is null && renamedId == "RPC 验证.json",
                rename.Error?.Message ?? "keyMouse.rename returned an invalid result.");

            var delete = await ExchangeAsync(
                connection, "recording-delete", "keyMouse.delete", sessionToken,
                JObject.FromObject(new { id = renamedId }), cancellationToken);
            var deleted = JObject.FromObject(delete.Result!);
            context.Require(
                delete.Error is null && deleted.Value<bool>("deleted"),
                delete.Error?.Message ?? "keyMouse.delete returned an invalid result.");
        }
        finally
        {
            serverCancellation.Cancel();
            await serverTask;
        }
    }

    private static async Task<RpcResponse> ExchangeAsync(
        FramedJsonConnection connection,
        string id,
        string method,
        string sessionToken,
        JObject? parameters,
        CancellationToken cancellationToken)
    {
        await connection.WriteRequestAsync(
            new RpcRequest(id, method, parameters, sessionToken), cancellationToken);
        return await connection.ReadResponseAsync(cancellationToken)
            ?? throw new EndOfStreamException($"Core disconnected during {method}.");
    }

    private static bool Throws<TException>(Action action)
        where TException : Exception
    {
        try
        {
            action();
            return false;
        }
        catch (TException)
        {
            return true;
        }
    }

    private static async Task<string> ReadHttpRequestBodyAsync(
        TcpListener listener,
        CancellationToken cancellationToken)
    {
        using var client = await listener.AcceptTcpClientAsync(cancellationToken);
        await using var stream = client.GetStream();
        using var reader = new StreamReader(
            stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: false,
            leaveOpen: true);
        var contentLength = 0;
        while (await reader.ReadLineAsync(cancellationToken) is { } line &&
               line.Length > 0)
        {
            const string contentLengthHeader = "Content-Length:";
            if (line.StartsWith(
                    contentLengthHeader,
                    StringComparison.OrdinalIgnoreCase))
            {
                contentLength = int.Parse(
                    line[contentLengthHeader.Length..].Trim());
            }
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
