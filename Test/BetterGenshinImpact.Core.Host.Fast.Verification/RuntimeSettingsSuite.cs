using BetterGenshinImpact.Core.Host;
using BetterGenshinImpact.Core.Host.Protocol;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Recorder;
using BetterGenshinImpact.Core.Recorder.Model;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Macro;
using BetterGenshinImpact.GameTask.QuickBuy;
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
                    "spaceFireInterval": 100,
                    "runaroundMouseXInterval": 240,
                    "runaroundInterval": 10,
                    "enhanceWaitDelay": 37
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
                runaroundMouseXInterval = 240,
                runaroundInterval = 10,
                enhanceWaitDelay = 37,
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

            var turnAroundPlatform =
                new RecordingTurnAroundRuntimePlatform(macroCatalog);
            TurnAroundRuntimePlatform.Configure(turnAroundPlatform);
            _ = macroCatalog.Save(JObject.FromObject(new
            {
                fPressHoldToContinuationEnabled = true,
                fFireInterval = 80,
                spacePressHoldToContinuationEnabled = true,
                spaceFireInterval = 120,
                runaroundMouseXInterval = 0,
                runaroundInterval = 10,
                enhanceWaitDelay = 37,
            }));
            TurnAroundMacro.Done(cancellationToken);
            context.Require(
                turnAroundPlatform.LastX == 1 &&
                macroCatalog.Snapshot().RunaroundMouseXInterval == 1,
                "Shared TurnAroundMacro did not preserve upstream zero-distance normalization.");
            _ = macroCatalog.Save(JObject.FromObject(new
            {
                fPressHoldToContinuationEnabled = true,
                fFireInterval = 80,
                spacePressHoldToContinuationEnabled = true,
                spaceFireInterval = 120,
                runaroundMouseXInterval = 240,
                runaroundInterval = 10,
                enhanceWaitDelay = 37,
            }));
            var quickEnhancePlatform =
                new RecordingQuickEnhanceArtifactRuntimePlatform(
                    macroCatalog.Snapshot().EnhanceWaitDelay);
            QuickEnhanceArtifactRuntimePlatform.Configure(quickEnhancePlatform);
            quickEnhancePlatform.IsInitialized = false;
            QuickEnhanceArtifactMacro.Done(cancellationToken);
            context.Require(
                quickEnhancePlatform.NotStartedCount == 1 &&
                quickEnhancePlatform.Operations.Count == 0,
                "Shared QuickEnhanceArtifactMacro did not preserve the upstream not-started guard.");
            quickEnhancePlatform.IsInitialized = true;
            QuickEnhanceArtifactMacro.Done(cancellationToken);
            context.Require(
                quickEnhancePlatform.Operations.SequenceEqual(
                [
                    "click:1760,770",
                    "wait:100",
                    "click:1760,1020",
                    "wait:137",
                    "click:150,150",
                    "wait:100",
                    "click:150,220",
                    "wait:100",
                    "move:1760,770",
                ]),
                "Shared QuickEnhanceArtifactMacro diverged from the upstream click and delay sequence.");
            var sereniteaQuickBuy = new RecordingQuickBuyRuntimePlatform();
            QuickBuyTask.Execute(
                sereniteaQuickBuy,
                isSereniteaPot: true,
                cancellationToken);
            context.Require(
                sereniteaQuickBuy.Operations.SequenceEqual(
                [
                    "move:1450,690",
                    "wait:100",
                    "down",
                    "wait:50",
                    "moveBy:1000,0",
                    "wait:200",
                    "up",
                    "wait:200",
                    "click:1600,1020",
                    "wait:200",
                    "click:960,850",
                ]),
                "Shared QuickBuyTask diverged from the upstream Serenitea Pot sequence.");
            var standardQuickBuy = new RecordingQuickBuyRuntimePlatform();
            QuickBuyTask.Execute(
                standardQuickBuy,
                isSereniteaPot: false,
                cancellationToken);
            context.Require(
                standardQuickBuy.Operations.SequenceEqual(
                [
                    "bottomRight:225,60",
                    "wait:100",
                    "move:742,601",
                    "wait:100",
                    "down",
                    "wait:50",
                    "moveBy:1000,0",
                    "wait:200",
                    "up",
                    "wait:100",
                    "click:1100,780",
                    "wait:200",
                    "bottomRight:225,60",
                    "wait:200",
                ]),
                "Shared QuickBuyTask diverged from the upstream standard-shop sequence.");
            using (var dragCancellation =
                   CancellationTokenSource.CreateLinkedTokenSource(
                       cancellationToken))
            {
                var cancelledQuickBuy =
                    new RecordingQuickBuyRuntimePlatform(
                        cancelOnWait: 50,
                        dragCancellation);
                context.Require(
                    Throws<OperationCanceledException>(() =>
                        QuickBuyTask.Execute(
                            cancelledQuickBuy,
                            isSereniteaPot: false,
                            dragCancellation.Token)) &&
                    cancelledQuickBuy.Operations.LastOrDefault() == "up",
                    "QuickBuyTask cancellation left the synthetic mouse button pressed.");
            }
            using (var holdHotKeys = new HoldHotKeyCoordinator(
                       cancellationToken,
                       loggerFactory.CreateLogger<HoldHotKeyCoordinator>(),
                       new Dictionary<string, Action<CancellationToken>>(
                           StringComparer.Ordinal)
                       {
                           [HoldHotKeyCoordinator.TurnAroundHotKey] =
                               TurnAroundMacro.Done,
                       }))
            {
                holdHotKeys.Start();
                var baselineMoveCount = turnAroundPlatform.MoveCount;
                var armed = JObject.FromObject(holdHotKeys.HandleKeyEdge(
                    HoldHotKeyCoordinator.TurnAroundHotKey, true));
                for (var retry = 0;
                     retry < 50 &&
                     turnAroundPlatform.MoveCount == baselineMoveCount;
                     retry++)
                {
                    await Task.Delay(10, cancellationToken);
                }
                var released = JObject.FromObject(holdHotKeys.HandleKeyEdge(
                    HoldHotKeyCoordinator.TurnAroundHotKey, false));
                await Task.Delay(30, cancellationToken);
                var moveCountAfterRelease = turnAroundPlatform.MoveCount;
                await Task.Delay(30, cancellationToken);
                context.Require(
                    armed.Value<string>("state") == "armed" &&
                    released.Value<string>("state") == "released" &&
                    turnAroundPlatform.LastX == 240 &&
                    moveCountAfterRelease > baselineMoveCount &&
                    turnAroundPlatform.MoveCount == moveCountAfterRelease,
                    "Turn-around hold hotkey did not preserve the upstream move, interval and release lifecycle.");
            }
            var confirmCount = 0;
            var cancelCount = 0;
            var dialogActions =
                new Dictionary<string, Action<CancellationToken>>(
                    StringComparer.Ordinal)
                {
                    [HoldHotKeyCoordinator.ConfirmButtonHotKey] = token =>
                    {
                        Interlocked.Increment(ref confirmCount);
                        if (token.WaitHandle.WaitOne(5))
                            token.ThrowIfCancellationRequested();
                    },
                    [HoldHotKeyCoordinator.CancelButtonHotKey] = token =>
                    {
                        Interlocked.Increment(ref cancelCount);
                        if (token.WaitHandle.WaitOne(5))
                            token.ThrowIfCancellationRequested();
                    },
                };
            using (var dialogHotKeys = new HoldHotKeyCoordinator(
                       cancellationToken,
                       loggerFactory.CreateLogger<HoldHotKeyCoordinator>(),
                       dialogActions))
            {
                dialogHotKeys.Start();
                _ = dialogHotKeys.HandleKeyEdge(
                    HoldHotKeyCoordinator.ConfirmButtonHotKey, true);
                _ = dialogHotKeys.HandleKeyEdge(
                    HoldHotKeyCoordinator.CancelButtonHotKey, true);
                for (var retry = 0;
                     retry < 50 &&
                     (Volatile.Read(ref confirmCount) == 0 ||
                      Volatile.Read(ref cancelCount) == 0);
                     retry++)
                {
                    await Task.Delay(10, cancellationToken);
                }
                _ = dialogHotKeys.HandleKeyEdge(
                    HoldHotKeyCoordinator.ConfirmButtonHotKey, false);
                await Task.Delay(30, cancellationToken);
                var confirmCountAfterRelease =
                    Volatile.Read(ref confirmCount);
                var cancelCountBeforeConfirmCheck =
                    Volatile.Read(ref cancelCount);
                await Task.Delay(30, cancellationToken);
                var cancelCountAfterConfirmCheck =
                    Volatile.Read(ref cancelCount);
                _ = dialogHotKeys.HandleKeyEdge(
                    HoldHotKeyCoordinator.CancelButtonHotKey, false);
                await Task.Delay(30, cancellationToken);
                var cancelCountAfterRelease =
                    Volatile.Read(ref cancelCount);
                await Task.Delay(30, cancellationToken);
                context.Require(
                    confirmCountAfterRelease > 0 &&
                    Volatile.Read(ref confirmCount) ==
                        confirmCountAfterRelease &&
                    cancelCountAfterConfirmCheck >
                        cancelCountBeforeConfirmCheck &&
                    Volatile.Read(ref cancelCount) ==
                        cancelCountAfterRelease,
                    "Independent dialog-button hold actions did not stop on their own release edges.");
            }
            var blockedInput = new ForegroundInputCoordinator(
                new PlatformCallbackChannel(),
                "verification",
                cancellationToken,
                TimeSpan.FromMilliseconds(5),
                () => false);
            var macTurnAround = new MacTurnAroundRuntimePlatform(
                macroCatalog, blockedInput, cancellationToken);
            using (var blockedCancellation =
                   CancellationTokenSource.CreateLinkedTokenSource(
                       cancellationToken))
            {
                var blockedMove = Task.Run(() =>
                {
                    try
                    {
                        macTurnAround.MoveMouseBy(
                            240, 0, blockedCancellation.Token);
                        return false;
                    }
                    catch (OperationCanceledException)
                    {
                        return true;
                    }
                }, cancellationToken);
                await Task.Delay(25, cancellationToken);
                blockedCancellation.Cancel();
                context.Require(
                    await blockedMove,
                    "Turn-around key-up could not cancel an input waiting for game focus.");
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
                hotKeys.Count == 25 &&
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
                hotKeys.Single(item =>
                    item.Value<string>("id") == "TurnAroundHotkey")
                    .Value<bool>("dispatchOnRelease") &&
                hotKeys.Single(item =>
                    item.Value<string>("id") ==
                        "ClickGenshinConfirmButtonHotkey")
                    .Value<bool>("isHold") &&
                hotKeys.Single(item =>
                    item.Value<string>("id") ==
                        "ClickGenshinConfirmButtonHotkey")
                    .Value<bool>("dispatchOnRelease") &&
                hotKeys.Single(item =>
                    item.Value<string>("id") ==
                        "ClickGenshinCancelButtonHotkey")
                    .Value<bool>("dispatchOnRelease") &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "EnhanceArtifactHotkey")
                    .Value<bool>("isHold") &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "EnhanceArtifactHotkey")
                    .Value<bool>("dispatchOnRelease") &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "QuickBuyHotkey")
                    .Value<bool>("isHold") &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "QuickBuyHotkey")
                    .Value<bool>("dispatchOnRelease") &&
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
                persisted["macroConfig"]?.Value<int>("runaroundMouseXInterval") == 240 &&
                persisted["macroConfig"]?.Value<int>("runaroundInterval") == 10 &&
                persisted["macroConfig"]?.Value<int>("enhanceWaitDelay") == 37 &&
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
        using var holdHotKeys = new HoldHotKeyCoordinator(
            serverCancellation.Token,
            loggerFactory.CreateLogger<HoldHotKeyCoordinator>(),
            new Dictionary<string, Action<CancellationToken>>(
                StringComparer.Ordinal)
            {
                [HoldHotKeyCoordinator.TurnAroundHotKey] =
                    TurnAroundMacro.Done,
                [HoldHotKeyCoordinator.ConfirmButtonHotKey] =
                    token =>
                    {
                        if (token.WaitHandle.WaitOne(5))
                            token.ThrowIfCancellationRequested();
                    },
                [HoldHotKeyCoordinator.CancelButtonHotKey] =
                    token =>
                    {
                        if (token.WaitHandle.WaitOne(5))
                            token.ThrowIfCancellationRequested();
                    },
            });
        server.AttachHoldHotKeyCoordinator(holdHotKeys);
        holdHotKeys.Start();
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
                        runaroundMouseXInterval = 260,
                        runaroundInterval = 12,
                        enhanceWaitDelay = 45,
                    }
                }), cancellationToken);
            var macroResult = JObject.FromObject(macroSave.Result!);
            context.Require(
                macroSave.Error is null &&
                macroResult.Value<int>("fFireInterval") == 70 &&
                macroResult.Value<int>("spaceFireInterval") == 130 &&
                macroResult.Value<int>("runaroundMouseXInterval") == 260 &&
                macroResult.Value<int>("runaroundInterval") == 12 &&
                macroResult.Value<int>("enhanceWaitDelay") == 45 &&
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

            var turnAroundDown = await ExchangeAsync(
                connection, "hotkey-turn-down", "hotKey.invoke", sessionToken,
                JObject.FromObject(new
                {
                    id = HoldHotKeyCoordinator.TurnAroundHotKey,
                    isDown = true,
                }), cancellationToken);
            var turnAroundUp = await ExchangeAsync(
                connection, "hotkey-turn-up", "hotKey.invoke", sessionToken,
                JObject.FromObject(new
                {
                    id = HoldHotKeyCoordinator.TurnAroundHotKey,
                    isDown = false,
                }), cancellationToken);
            context.Require(
                turnAroundDown.Error is null &&
                JObject.FromObject(turnAroundDown.Result!)
                    .Value<string>("state") == "armed" &&
                turnAroundUp.Error is null &&
                JObject.FromObject(turnAroundUp.Result!)
                    .Value<string>("state") == "released",
                turnAroundDown.Error?.Message ??
                turnAroundUp.Error?.Message ??
                "hotKey.invoke did not preserve the hold edge contract.");
            foreach (var dialogHotKey in new[]
                     {
                         HoldHotKeyCoordinator.ConfirmButtonHotKey,
                         HoldHotKeyCoordinator.CancelButtonHotKey,
                     })
            {
                var down = await ExchangeAsync(
                    connection, $"hotkey-{dialogHotKey}-down",
                    "hotKey.invoke", sessionToken,
                    JObject.FromObject(new
                    {
                        id = dialogHotKey,
                        isDown = true,
                    }), cancellationToken);
                var up = await ExchangeAsync(
                    connection, $"hotkey-{dialogHotKey}-up",
                    "hotKey.invoke", sessionToken,
                    JObject.FromObject(new
                    {
                        id = dialogHotKey,
                        isDown = false,
                    }), cancellationToken);
                context.Require(
                    down.Error is null &&
                    JObject.FromObject(down.Result!)
                        .Value<string>("state") == "armed" &&
                    up.Error is null &&
                    JObject.FromObject(up.Result!)
                        .Value<string>("state") == "released",
                    down.Error?.Message ??
                    up.Error?.Message ??
                    $"hotKey.invoke did not preserve {dialogHotKey} hold edges.");
            }
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

    private sealed class RecordingTurnAroundRuntimePlatform(
        MacroSettingsCatalog settings) : ITurnAroundRuntimePlatform
    {
        private int _moveCount;
        private int _lastX;

        public int RunaroundInterval => settings.Snapshot().RunaroundInterval;
        public int RunaroundMouseXInterval
        {
            get => settings.Snapshot().RunaroundMouseXInterval;
            set => settings.SetRunaroundMouseXInterval(value);
        }
        public int MoveCount => Volatile.Read(ref _moveCount);
        public int LastX => Volatile.Read(ref _lastX);

        public void MoveMouseBy(
            int x,
            int y,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Volatile.Write(ref _lastX, x);
            Interlocked.Increment(ref _moveCount);
        }

        public void Wait(int milliseconds, CancellationToken cancellationToken) =>
            Task.Delay(milliseconds, cancellationToken).GetAwaiter().GetResult();
    }

    private sealed class RecordingQuickEnhanceArtifactRuntimePlatform(
        int enhanceWaitDelay) : IQuickEnhanceArtifactRuntimePlatform
    {
        public bool IsInitialized { get; set; }
        public int EnhanceWaitDelay { get; } = enhanceWaitDelay;
        public int NotStartedCount { get; private set; }
        public List<string> Operations { get; } = [];

        public void NotifyNotStarted() => NotStartedCount++;

        public void ClickGame1080P(
            double x,
            double y,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Operations.Add($"click:{x:0},{y:0}");
        }

        public void MoveGame1080P(
            double x,
            double y,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Operations.Add($"move:{x:0},{y:0}");
        }

        public void Wait(int milliseconds, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Operations.Add($"wait:{milliseconds}");
        }
    }

    private sealed class RecordingQuickBuyRuntimePlatform(
        int? cancelOnWait = null,
        CancellationTokenSource? cancellation = null)
        : IQuickBuyRuntimePlatform
    {
        public bool IsInitialized => true;
        public bool IsGameProcessActive => true;
        public List<string> Operations { get; } = [];

        public void NotifyNotStarted() =>
            throw new InvalidOperationException("Unexpected not-started notification.");

        public BetterGenshinImpact.GameTask.Model.Area.ImageRegion Capture() =>
            throw new InvalidOperationException("Sequence verification does not capture.");

        public void MoveGame1080P(
            double x,
            double y,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Operations.Add($"move:{x:0},{y:0}");
        }

        public void ClickGame1080P(
            double x,
            double y,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Operations.Add($"click:{x:0},{y:0}");
        }

        public void ClickFromBottomRight1080P(
            double x,
            double y,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Operations.Add($"bottomRight:{x:0},{y:0}");
        }

        public void MoveMouseBy(
            int x,
            int y,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Operations.Add($"moveBy:{x},{y}");
        }

        public void LeftButtonDown(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Operations.Add("down");
        }

        public void LeftButtonUp(CancellationToken cancellationToken) =>
            Operations.Add("up");

        public void Wait(int milliseconds, CancellationToken cancellationToken)
        {
            Operations.Add($"wait:{milliseconds}");
            if (cancelOnWait == milliseconds && cancellation is not null)
                cancellation.Cancel();
            cancellationToken.ThrowIfCancellationRequested();
        }

        public void ClearOverlay() => Operations.Add("clear");

        public void LogWarning(Exception exception) =>
            Operations.Add($"warning:{exception.GetType().Name}");
    }
}
