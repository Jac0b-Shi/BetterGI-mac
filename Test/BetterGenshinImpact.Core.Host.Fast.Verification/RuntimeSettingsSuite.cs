using BetterGenshinImpact.Core.Host;
using BetterGenshinImpact.Core.Host.Protocol;
using BetterGenshinImpact.Core.Host.Runtime;
using BetterGenshinImpact.Core.Host.Transport;
using BetterGenshinImpact.Core.Recorder;
using BetterGenshinImpact.Core.Recorder.Model;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.AutoFight;
using BetterGenshinImpact.GameTask.AutoPathing;
using BetterGenshinImpact.GameTask.Macro;
using BetterGenshinImpact.GameTask.QuickBuy;
using BetterGenshinImpact.GameTask.QuickClaimReward;
using BetterGenshinImpact.GameTask.QuickSereniteaPot;
using BetterGenshinImpact.Service.Notification;
using BetterGenshinImpact.Verification.Framework;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
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
                    "enhanceWaitDelay": 37,
                    "combatMacroEnabled": false,
                    "combatMacroHotkeyMode": "按住时重复(新)",
                    "combatMacroPriority": 1,
                    "oneKeyClaimRewardHotkeyMode": "点按一次",
                    "oneKeyClaimRewardScrollDownEnabled": false,
                    "oneKeyClaimRewardScrollDownAmount": 2
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
                combatMacroEnabled = true,
                combatMacroHotkeyMode = OneKeyFightTask.TickMode,
                combatMacroPriority = 3,
                oneKeyClaimRewardHotkeyMode =
                    OneKeyClaimRewardTask.HoldMode,
                oneKeyClaimRewardScrollDownEnabled = true,
                oneKeyClaimRewardScrollDownAmount = 23,
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
                combatMacroEnabled = true,
                combatMacroHotkeyMode = OneKeyFightTask.TickMode,
                combatMacroPriority = 3,
                oneKeyClaimRewardHotkeyMode =
                    OneKeyClaimRewardTask.HoldMode,
                oneKeyClaimRewardScrollDownEnabled = true,
                oneKeyClaimRewardScrollDownAmount = 23,
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
                combatMacroEnabled = true,
                combatMacroHotkeyMode = OneKeyFightTask.TickMode,
                combatMacroPriority = 3,
                oneKeyClaimRewardHotkeyMode =
                    OneKeyClaimRewardTask.HoldMode,
                oneKeyClaimRewardScrollDownEnabled = true,
                oneKeyClaimRewardScrollDownAmount = 23,
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
            var claimRewardPlatform =
                new RecordingOneKeyClaimRewardRuntimePlatform(
                    new OneKeyClaimRewardSettings(
                        OneKeyClaimRewardTask.HoldMode,
                        ScrollDownEnabled: true,
                        ScrollDownAmount: 23));
            OneKeyClaimRewardRuntimePlatform.Configure(claimRewardPlatform);
            var avatarMacroPath = Path.Combine(
                layout.UserPath,
                "avatar_macro.json");
            var oneKeyFightPlatform =
                new RecordingOneKeyFightRuntimePlatform(
                    new OneKeyFightSettings(
                        Enabled: true,
                        HotkeyMode: OneKeyFightTask.TickMode,
                        Priority: 3),
                    avatarMacroPath);
            OneKeyFightRuntimePlatform.Configure(oneKeyFightPlatform);
            context.Require(
                OneKeyFightTask.IsEnabled() &&
                OneKeyFightTask.IsTickMode() &&
                !OneKeyFightTask.IsHoldOnMode() &&
                !OneKeyFightTask.IsHoldFinishMode() &&
                OneKeyFightTask.GetAvatarMacroJsonPath() == avatarMacroPath,
                "OneKeyFightTask did not consume the composed settings and avatar-macro path.");
            OneKeyClaimRewardTask.ScrollDown(
                claimRewardPlatform,
                configuredAmount: 23,
                cancellationToken);
            context.Require(
                OneKeyClaimRewardTask.IsHoldMode(
                    claimRewardPlatform.Settings) &&
                OneKeyClaimRewardTask.CanScrollDown(
                    claimRewardPlatform.Settings) &&
                claimRewardPlatform.Scrolls.SequenceEqual([-10, -10, -3]),
                "OneKeyClaimRewardTask drifted from the upstream hold-mode scroll chunking.");
            var quickSereniteaPotPlatform =
                new RecordingQuickSereniteaPotRuntimePlatform
                {
                    IsInitialized = false,
                    IsGameProcessActive = true,
                };
            QuickSereniteaPotRuntimePlatform.Configure(
                quickSereniteaPotPlatform);
            QuickSereniteaPotTask.Done(cancellationToken);
            quickSereniteaPotPlatform.IsInitialized = true;
            quickSereniteaPotPlatform.IsGameProcessActive = false;
            QuickSereniteaPotTask.Done(cancellationToken);
            context.Require(
                quickSereniteaPotPlatform.NotStartedCount == 1 &&
                quickSereniteaPotPlatform.Operations.Count == 0,
                "QuickSereniteaPotTask bypassed its upstream runtime or focus guard.");
            QuickSereniteaPotTask.CompleteInteraction(
                quickSereniteaPotPlatform,
                isEnter: true,
                isLeave: false,
                cancellationToken);
            context.Require(
                quickSereniteaPotPlatform.Operations.SequenceEqual(
                [
                    "info:快速进出尘歌壶:识别到 进入尘歌壶",
                    "action:PickUpOrInteract",
                    "info:快速进出尘歌壶:F进入尘歌壶",
                    "wait:200",
                    "click:1010,760",
                ]),
                "QuickSereniteaPotTask diverged from the upstream enter interaction sequence.");
            quickSereniteaPotPlatform.Operations.Clear();
            QuickSereniteaPotTask.CompleteInteraction(
                quickSereniteaPotPlatform,
                isEnter: false,
                isLeave: false,
                cancellationToken);
            context.Require(
                quickSereniteaPotPlatform.Operations.SequenceEqual(
                ["info:快速进出尘歌壶:未识别到 进入或离开尘歌壶"]),
                "QuickSereniteaPotTask sent input without recognizing the upstream interaction text.");
            claimRewardPlatform.IsInitialized = false;
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
                           [HoldHotKeyCoordinator.OneKeyClaimRewardHotKey] =
                               OneKeyClaimRewardTask.Instance.RunHotKey,
                           [HoldHotKeyCoordinator.OneKeyFightHotKey] =
                               token =>
                               {
                                   if (token.WaitHandle.WaitOne(5))
                                       token.ThrowIfCancellationRequested();
                               },
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
                _ = holdHotKeys.HandleKeyEdge(
                    HoldHotKeyCoordinator.OneKeyClaimRewardHotKey,
                    true);
                await Task.Delay(20, cancellationToken);
                _ = holdHotKeys.HandleKeyEdge(
                    HoldHotKeyCoordinator.OneKeyClaimRewardHotKey,
                    false);
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
                context.Require(
                    claimRewardPlatform.NotStartedCount == 1 &&
                    claimRewardPlatform.CaptureCount == 0,
                    "One-key claim reward bypassed the runtime-start guard.");
            }
            using (var oneShotStarted = new ManualResetEventSlim())
            {
                var invocationCount = 0;
                using var oneShotHotKeys = new OneShotHotKeyCoordinator(
                    cancellationToken,
                    loggerFactory.CreateLogger<OneShotHotKeyCoordinator>(),
                    new Dictionary<string, Action<CancellationToken>>(
                        StringComparer.Ordinal)
                    {
                        [OneShotHotKeyCoordinator.QuickSereniteaPotHotKey] =
                            token =>
                            {
                                Interlocked.Increment(ref invocationCount);
                                oneShotStarted.Set();
                                token.WaitHandle.WaitOne();
                                token.ThrowIfCancellationRequested();
                            },
                    });
                oneShotHotKeys.Start();
                var started = JObject.FromObject(oneShotHotKeys.Invoke(
                    OneShotHotKeyCoordinator.QuickSereniteaPotHotKey));
                context.Require(
                    oneShotStarted.Wait(TimeSpan.FromSeconds(1)),
                    "One-shot Serenitea Pot hotkey did not start its Core action.");
                var running = JObject.FromObject(oneShotHotKeys.Invoke(
                    OneShotHotKeyCoordinator.QuickSereniteaPotHotKey));
                await oneShotHotKeys.StopAsync();
                var stopped = JObject.FromObject(oneShotHotKeys.Invoke(
                    OneShotHotKeyCoordinator.QuickSereniteaPotHotKey));
                context.Require(
                    started.Value<string>("state") == "started" &&
                    running.Value<string>("state") == "running" &&
                    stopped.Value<string>("state") == "stopped" &&
                    Volatile.Read(ref invocationCount) == 1,
                    "One-shot Serenitea Pot hotkey did not deduplicate or cancel with runtime stop.");
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
                () => null,
                loggerFactory.CreateLogger<NotificationSettingsCatalog>());
            notificationCatalog.AttachScriptHostServices(scriptHostServices);
            _ = notificationCatalog.Save(JObject.FromObject(new
            {
                includeScreenShot = false,
                jsNotificationEnabled = true,
                macOSNotificationEnabled = true,
                notificationEventSubscribe = "js.error,js.custom,JS.ERROR",
                webhookEnabled = false,
                webhookEndpoint = "",
                webhookSendTo = "verification",
            }));
            var notificationSettings = JObject.FromObject(notificationCatalog.Get());
            var notificationEvents = (JArray)notificationSettings["events"]!;
            var notificationChannels = (JArray)notificationSettings["channels"]!;
            context.Require(
                !notificationSettings.Value<bool>("includeScreenShot") &&
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
                notificationChannels.Count == 13 &&
                notificationChannels.Any(channel =>
                    channel.Value<string>("id") == "telegram" &&
                    channel.Value<string>("enabledField") ==
                        "telegramNotificationEnabled" &&
                    ((JArray)channel["fields"]!).Any(field =>
                        field.Value<string>("id") == "telegramBotToken" &&
                        field.Value<string>("kind") == "secret")) &&
                notificationChannels.Any(channel =>
                    channel.Value<string>("id") == "email" &&
                    ((JArray)channel["fields"]!).Any(field =>
                        field.Value<string>("id") == "smtpPort" &&
                        field.Value<string>("kind") == "integer")),
                "Notification settings did not expose the complete Core-owned upstream channel schema.");
            var telegramSettings = JObject.FromObject(
                notificationCatalog.SaveChannel(
                    "telegram",
                    JObject.FromObject(new
                    {
                        telegramNotificationEnabled = true,
                        telegramBotToken = "verification-token",
                        telegramChatId = "verification-chat",
                        telegramApiBaseUrl = "",
                        telegramProxyEnabled = false,
                        telegramProxyUrl = "http://127.0.0.1:10809",
                    })));
            var telegramChannel = ((JArray)telegramSettings["channels"]!)
                .Single(channel => channel.Value<string>("id") == "telegram");
            context.Require(
                telegramChannel.Value<bool>("enabled") &&
                ((JArray)telegramChannel["fields"]!).Any(field =>
                    field.Value<string>("id") == "telegramBotToken" &&
                    field.Value<string>("value") == "verification-token") &&
                ((JArray)telegramChannel["fields"]!).Any(field =>
                    field.Value<string>("id") == "telegramProxyEnabled" &&
                    !field.Value<bool>("value")),
                "Notification channel save did not atomically preserve typed Telegram settings.");
            _ = notificationCatalog.SaveChannel(
                "serverChan",
                JObject.FromObject(new
                {
                    serverChanNotificationEnabled = true,
                    serverChanSendKey = "",
                }));
            context.Require(
                JObject.FromObject(notificationCatalog.Get())
                    .SelectToken("channels[?(@.id == 'serverChan')].enabled")!
                    .Value<bool>() &&
                await ThrowsAsync<InvalidOperationException>(
                    () => notificationCatalog.TestAsync("serverChan")),
                "Notification channels did not preserve upstream save-first, validate-on-test semantics.");
            _ = notificationCatalog.SaveChannel(
                "serverChan",
                JObject.FromObject(new
                {
                    serverChanNotificationEnabled = false,
                }));
            _ = notificationCatalog.SaveChannel(
                "telegram",
                JObject.FromObject(new
                {
                    telegramNotificationEnabled = false,
                }));
            context.Require(
                Throws<ArgumentException>(() => notificationCatalog.Save(
                    JObject.FromObject(new
                    {
                        includeScreenShot = false,
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
                includeScreenShot = false,
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
                    "这是一条测试通知信息",
                $"The shared upstream NotificationService sent an unexpected Webhook test payload: {webhookPayload}");

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
                hotKeys.Count == 31 &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "TakeScreenshotHotkey")
                    .Value<string>("action") == "capture.screenshot" &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "PathRecorderHotkey")
                    .Value<string>("action") == "pathRecorder.toggle" &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "AddWaypointHotkey")
                    .Value<string>("action") == "pathRecorder.addWaypoint" &&
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
                !hotKeys.Single(item =>
                    item.Value<string>("id") ==
                        "QuickSereniteaPotHotkey")
                    .Value<bool>("isHold") &&
                hotKeys.Single(item =>
                    item.Value<string>("id") ==
                        "QuickSereniteaPotHotkey")
                    .Value<bool>("dispatchOnPress") &&
                !hotKeys.Single(item =>
                    item.Value<string>("id") ==
                        "QuickSereniteaPotHotkey")
                    .Value<bool>("dispatchOnRelease") &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "OneKeyClaimRewardHotkey")
                    .Value<bool>("isHold") &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "OneKeyClaimRewardHotkey")
                    .Value<bool>("dispatchOnRelease") &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "OneKeyFightHotkey")
                    .Value<bool>("isHold") &&
                hotKeys.Single(item =>
                    item.Value<string>("id") == "OneKeyFightHotkey")
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
                persisted["macroConfig"]?.Value<bool>(
                    "combatMacroEnabled") == true &&
                persisted["macroConfig"]?.Value<string>(
                    "combatMacroHotkeyMode") ==
                    OneKeyFightTask.TickMode &&
                persisted["macroConfig"]?.Value<int>(
                    "combatMacroPriority") == 3 &&
                persisted["macroConfig"]?.Value<string>(
                    "oneKeyClaimRewardHotkeyMode") ==
                    OneKeyClaimRewardTask.HoldMode &&
                persisted["macroConfig"]?.Value<bool>(
                    "oneKeyClaimRewardScrollDownEnabled") == true &&
                persisted["macroConfig"]?.Value<int>(
                    "oneKeyClaimRewardScrollDownAmount") == 23 &&
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
        var screenshotPath = Path.Combine(
            layout.LogPath, "screenshot", "verification.png");
        var screenshotAction = new RecordingGameScreenshotAction(screenshotPath);
        server.AttachGameScreenshotAction(screenshotAction);
        var pathRecorder = new RecordingPathRecorderAction();
        server.AttachPathRecorder(pathRecorder);
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
                [HoldHotKeyCoordinator.OneKeyClaimRewardHotKey] =
                    token =>
                    {
                        if (token.WaitHandle.WaitOne(5))
                            token.ThrowIfCancellationRequested();
                    },
                [HoldHotKeyCoordinator.OneKeyFightHotKey] =
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

            var schedulerStatus = await ExchangeAsync(
                connection, "scheduler-status", "scheduler.status", sessionToken,
                null, cancellationToken);
            var schedulerStatusResult = JObject.FromObject(schedulerStatus.Result!);
            context.Require(
                schedulerStatus.Error is null &&
                schedulerStatusResult.Value<string>("state") == "idle" &&
                schedulerStatusResult["taskId"]?.Type == JTokenType.Null,
                schedulerStatus.Error?.Message ??
                "scheduler.status did not expose the initial idle state.");

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
                        combatMacroEnabled = true,
                        combatMacroHotkeyMode =
                            OneKeyFightTask.HoldOnMode,
                        combatMacroPriority = 4,
                        oneKeyClaimRewardHotkeyMode =
                            OneKeyClaimRewardTask.HoldMode,
                        oneKeyClaimRewardScrollDownEnabled = true,
                        oneKeyClaimRewardScrollDownAmount = 17,
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
                macroResult.Value<bool>("combatMacroEnabled") &&
                macroResult.Value<string>("combatMacroHotkeyMode") ==
                    OneKeyFightTask.HoldOnMode &&
                ((JArray)macroResult["combatMacroHotkeyModeOptions"]!)
                    .Values<string>()
                    .SequenceEqual(
                    [
                        OneKeyFightTask.HoldOnMode,
                        OneKeyFightTask.HoldFinishMode,
                        OneKeyFightTask.TickMode,
                    ]) &&
                macroResult.Value<int>("combatMacroPriority") == 4 &&
                macroResult.Value<string>(
                    "oneKeyClaimRewardHotkeyMode") ==
                    OneKeyClaimRewardTask.HoldMode &&
                macroResult.Value<string>(
                    "oneKeyClaimRewardHoldMode") ==
                    OneKeyClaimRewardTask.HoldMode &&
                ((JArray)macroResult[
                    "oneKeyClaimRewardHotkeyModeOptions"]!)
                    .Values<string>()
                    .SequenceEqual(
                    [
                        OneKeyClaimRewardTask.ClickOnceMode,
                        OneKeyClaimRewardTask.HoldMode,
                    ]) &&
                macroResult.Value<bool>(
                    "oneKeyClaimRewardScrollDownEnabled") &&
                macroResult.Value<int>(
                    "oneKeyClaimRewardScrollDownAmount") == 17 &&
                macroResult.Value<int>("pickUpOrInteractKeyCode") == 71 &&
                macroResult.Value<int>("jumpKeyCode") == 74,
                macroSave.Error?.Message ?? "macro.settings.save returned an invalid result.");

            var avatarMacroLocation = await ExchangeAsync(
                connection,
                "macro-avatar-location",
                "macro.avatar.location",
                sessionToken,
                null,
                cancellationToken);
            context.Require(
                avatarMacroLocation.Error is null &&
                JObject.FromObject(avatarMacroLocation.Result!)
                    .Value<string>("path") ==
                    Path.Combine(layout.UserPath, "avatar_macro.json"),
                avatarMacroLocation.Error?.Message ??
                "macro.avatar.location did not return the Core-owned macro path.");

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
                    item.Value<string>("hotKey") == "F11") &&
                hotKeyListResult.Any(item =>
                    item.Value<string>("id") == "TakeScreenshotHotkey" &&
                    item.Value<string>("action") == "capture.screenshot" &&
                    item.Value<string>("executionOwner") == "core") &&
                hotKeyListResult.Any(item =>
                    item.Value<string>("id") == "PathRecorderHotkey" &&
                    item.Value<string>("category") == "开发者" &&
                    item.Value<string>("executionOwner") == "core") &&
                hotKeyListResult.Any(item =>
                    item.Value<string>("id") == "AddWaypointHotkey" &&
                    item.Value<string>("executionOwner") == "core"),
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
                         HoldHotKeyCoordinator.OneKeyClaimRewardHotKey,
                         HoldHotKeyCoordinator.OneKeyFightHotKey,
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

            var screenshot = await ExchangeAsync(
                connection, "hotkey-screenshot", "hotKey.invoke",
                sessionToken, JObject.FromObject(new
                {
                    id = "TakeScreenshotHotkey",
                }), cancellationToken);
            var screenshotResult = JObject.FromObject(screenshot.Result!);
            context.Require(
                screenshot.Error is null &&
                screenshotResult.Value<string>("state") == "saved" &&
                screenshotResult.Value<string>("path") == screenshotPath &&
                screenshotAction.InvocationCount == 1 &&
                File.Exists(screenshotPath),
                screenshot.Error?.Message ??
                    "hotKey.invoke did not execute the Core-owned screenshot action.");

            var pathStart = await ExchangeAsync(
                connection, "hotkey-path-start", "hotKey.invoke",
                sessionToken, JObject.FromObject(new
                {
                    id = "PathRecorderHotkey",
                }), cancellationToken);
            var pathAdd = await ExchangeAsync(
                connection, "hotkey-path-add", "hotKey.invoke",
                sessionToken, JObject.FromObject(new
                {
                    id = "AddWaypointHotkey",
                }), cancellationToken);
            var pathSave = await ExchangeAsync(
                connection, "hotkey-path-save", "hotKey.invoke",
                sessionToken, JObject.FromObject(new
                {
                    id = "PathRecorderHotkey",
                }), cancellationToken);
            context.Require(
                pathStart.Error is null &&
                JObject.FromObject(pathStart.Result!)
                    .Value<string>("state") == "recording" &&
                pathAdd.Error is null &&
                JObject.FromObject(pathAdd.Result!)
                    .Value<string>("state") == "waypointAdded" &&
                pathSave.Error is null &&
                JObject.FromObject(pathSave.Result!)
                    .Value<string>("state") == "saved" &&
                pathRecorder.ToggleCount == 2 &&
                pathRecorder.AddCount == 1,
                pathStart.Error?.Message ??
                    pathAdd.Error?.Message ??
                    pathSave.Error?.Message ??
                    "hotKey.invoke did not route path recorder actions through Core.");

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

    private static async Task<bool> ThrowsAsync<TException>(
        Func<Task> action)
        where TException : Exception
    {
        try
        {
            await action();
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

    private sealed class RecordingQuickSereniteaPotRuntimePlatform
        : IQuickSereniteaPotRuntimePlatform
    {
        public bool IsInitialized { get; set; }
        public bool IsGameProcessActive { get; set; }
        public int NotStartedCount { get; private set; }
        public List<string> Operations { get; } = [];

        public void NotifyNotStarted() => NotStartedCount++;

        public BetterGenshinImpact.GameTask.Model.Area.ImageRegion Capture(
            bool forceNew,
            CancellationToken cancellationToken) =>
            throw new InvalidOperationException(
                "Guard and interaction verification must not capture.");

        public void SimulateAction(
            BetterGenshinImpact.Core.Simulator.Extensions.GIActions action,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Operations.Add($"action:{action}");
        }

        public void ClickGame1080P(
            double x,
            double y,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Operations.Add($"click:{x:0},{y:0}");
        }

        public void Wait(
            int milliseconds,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Operations.Add($"wait:{milliseconds}");
        }

        public void ClearOverlay() => Operations.Add("clear");

        public void LogInformation(string message) =>
            Operations.Add($"info:{message}");

        public void LogWarning(Exception exception) =>
            Operations.Add($"warning:{exception.GetType().Name}");
    }

    private sealed class RecordingOneKeyClaimRewardRuntimePlatform(
        OneKeyClaimRewardSettings settings)
        : IOneKeyClaimRewardRuntimePlatform
    {
        public bool IsInitialized { get; set; } = true;
        public bool IsGameProcessActive => true;
        public OneKeyClaimRewardSettings Settings { get; } = settings;
        public ILogger Logger { get; } =
            NullLogger<RecordingOneKeyClaimRewardRuntimePlatform>.Instance;
        public int NotStartedCount { get; private set; }
        public int CaptureCount { get; private set; }
        public List<int> Scrolls { get; } = [];

        public void NotifyNotStarted() => NotStartedCount++;

        public BetterGenshinImpact.GameTask.Model.Area.ImageRegion Capture(
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CaptureCount++;
            throw new InvalidOperationException(
                "The not-started contract must not capture.");
        }

        public void Click(
            BetterGenshinImpact.GameTask.Model.Area.Region region,
            CancellationToken cancellationToken) =>
            throw new InvalidOperationException(
                "The not-started contract must not click.");

        public void PressEscape(CancellationToken cancellationToken) =>
            throw new InvalidOperationException(
                "The not-started contract must not press Escape.");

        public void VerticalScroll(
            int clicks,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Scrolls.Add(clicks);
        }
    }

    private sealed class RecordingOneKeyFightRuntimePlatform(
        OneKeyFightSettings settings,
        string avatarMacroPath)
        : IOneKeyFightRuntimePlatform
    {
        public OneKeyFightSettings Settings { get; } = settings;
        public ILogger Logger { get; } =
            NullLogger<RecordingOneKeyFightRuntimePlatform>.Instance;

        public string EnsureAvatarMacroPath() => avatarMacroPath;
    }

    private sealed class RecordingGameScreenshotAction(string path)
        : IGameScreenshotAction
    {
        public int InvocationCount { get; private set; }

        public string TakeScreenshot(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            InvocationCount++;
            Directory.CreateDirectory(
                Path.GetDirectoryName(path)
                ?? throw new InvalidOperationException(
                    "Screenshot verification path omitted its directory."));
            File.WriteAllText(path, "screenshot");
            return path;
        }
    }

    private sealed class RecordingPathRecorderAction : IPathRecorderAction
    {
        public int ToggleCount { get; private set; }
        public int AddCount { get; private set; }

        public PathRecorderResult Toggle()
        {
            ToggleCount++;
            return new PathRecorderResult(
                ToggleCount == 1 ? "recording" : "saved",
                ToggleCount == 1 ? 1 : 2,
                ToggleCount == 1 ? null : "verification.json");
        }

        public PathRecorderResult AddWaypoint(string waypointType = "")
        {
            AddCount++;
            return new PathRecorderResult("waypointAdded", 2);
        }
    }
}
