using BetterGenshinImpact.Core.Abstractions.Recognition;
using BetterGenshinImpact.Core.Abstractions.Runtime;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Runtime.Windows;
using BetterGenshinImpact.GameTask.AutoPick.Assets;
using BetterGenshinImpact.GameTask.Common;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Screenshot;
using BetterGenshinImpact.Platform.Abstractions;
using BetterGenshinImpact.GameTask.GameLoading;
using BetterGenshinImpact.Helpers;
using BetterGenshinImpact.Service;
using BetterGenshinImpact.View;
using Fischless.GameCapture;
using Fischless.GameCapture.Graphics;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;

namespace BetterGenshinImpact.GameTask
{
    public class TaskTriggerDispatcher : IDisposable
    {
        private readonly ILogger<TaskTriggerDispatcher> _logger = App.GetLogger<TaskTriggerDispatcher>();
        private readonly OverlayMetricsService? _metricsService = App.GetService<OverlayMetricsService>();
        private readonly CustomHtmlMaskService? _customHtmlMaskService = App.GetService<CustomHtmlMaskService>();

        private static TaskTriggerDispatcher? _instance;

        private readonly CaptureTriggerScheduler _captureTriggerScheduler;
        private readonly OverlayWindowScheduler _overlayWindowScheduler;

        public IGameCapture? GameCapture { get; private set; }

        public event EventHandler? UiTaskStopTickEvent;

        public event EventHandler? UiTaskStartTickEvent;

        private readonly IAutoPickConfigProvider _autoPickConfigProvider;
        private readonly IAutoPickRuntimeState _runtimeState;
        private readonly IInputBackend _inputBackend;
        private readonly IPaddleAutoPickTextRecognizer _paddleRecognizer;
        private readonly IYapAutoPickTextRecognizer _yapRecognizer;
        private ISystemInfo? _systemInfo;
        private bool _started;
        private bool _starting;
        private bool _startFailed;

        public TaskTriggerDispatcher(
            IAutoPickConfigProvider autoPickConfigProvider,
            IAutoPickRuntimeState runtimeState,
            IInputBackend inputBackend,
            IPaddleAutoPickTextRecognizer paddleRecognizer,
            IYapAutoPickTextRecognizer yapRecognizer)
        {
            ArgumentNullException.ThrowIfNull(autoPickConfigProvider);
            ArgumentNullException.ThrowIfNull(runtimeState);
            ArgumentNullException.ThrowIfNull(inputBackend);
            ArgumentNullException.ThrowIfNull(paddleRecognizer);
            ArgumentNullException.ThrowIfNull(yapRecognizer);
            _autoPickConfigProvider = autoPickConfigProvider;
            _runtimeState = runtimeState;
            _inputBackend = inputBackend;
            _paddleRecognizer = paddleRecognizer;
            _yapRecognizer = yapRecognizer;
            _instance = this;
            _captureTriggerScheduler = new CaptureTriggerScheduler(
                _logger,
                _metricsService,
                () => GameCapture,
                () => RequireSystemInfo(),
                _autoPickConfigProvider,
                _runtimeState,
                _inputBackend,
                _paddleRecognizer,
                _yapRecognizer);
            _overlayWindowScheduler = new OverlayWindowScheduler(
                _logger,
                _customHtmlMaskService,
                () => GameCapture,
                _captureTriggerScheduler.GetTriggerActivityState,
                _captureTriggerScheduler.UpdateAvailabilityState,
                _captureTriggerScheduler.RequestSkipNextFrame,
                OnUiTaskStopTick);
        }

        private ISystemInfo RequireSystemInfo() =>
            _systemInfo ?? throw new InvalidOperationException(
                "TaskTriggerDispatcher.Start() must be called first.");

        public static TaskTriggerDispatcher Instance()
        {
            if (_instance == null)
            {
                throw new Exception("请先在启动页启动BetterGI，如果已经启动请重启");
            }

            return _instance;
        }

        public static IGameCapture GlobalGameCapture
        {
            get
            {
                _instance = Instance();

                if (_instance.GameCapture == null)
                {
                    throw new Exception("截图器未初始化!");
                }

                return _instance.GameCapture;
            }
        }

        public void ClearTriggers()
        {
            _captureTriggerScheduler.ClearTriggers();
        }

        public void SetTriggers(List<ITaskTrigger> list)
        {
            _captureTriggerScheduler.SetTriggers(list);
        }

        public bool AddTrigger(string name, object? externalConfig)
        {
            return _captureTriggerScheduler.AddTrigger(name, externalConfig);
        }

        /// <summary>
        /// Reload initial triggers via GameTaskManager, forwarding the composed runtime dependencies.
        /// </summary>
        public void ReloadInitialTriggers()
        {
            _captureTriggerScheduler.SetTriggers(GameTaskManager.LoadInitialTriggers(
                _inputBackend,
                RequireSystemInfo(),
                _runtimeState,
                _autoPickConfigProvider,
                _paddleRecognizer,
                _yapRecognizer));
        }

        public void Start(IntPtr hWnd, CaptureModes mode, int interval = 50)
        {
            if (_started)
                throw new InvalidOperationException("TaskTriggerDispatcher has already been started.");
            if (_startFailed)
                throw new InvalidOperationException(
                    "TaskTriggerDispatcher startup previously failed and may be partially initialized. " +
                    "Restart the application before trying again.");
            if (_starting)
                throw new InvalidOperationException("TaskTriggerDispatcher is already in the process of starting.");

            _starting = true;
            try
            {
                ChatUiHotkeyGuard.Reset();
                GameCapture = GameCaptureFactory.Create(mode);
                SystemControl.ActivateWindow(hWnd);

                TaskContext.Instance().Init(hWnd);
                _systemInfo = TaskContext.Instance().SystemInfo;
                ReloadInitialTriggers();
                GameLoadingTrigger.GlobalEnabled = TaskContext.Instance().Config.GenshinStartConfig.AutoEnterGameEnabled;

                GameCapture.Start(hWnd,
                    new Dictionary<string, object>()
                    {
                        { "autoFixWin11BitBlt", OsVersionHelper.IsWindows11_OrGreater && TaskContext.Instance().Config.AutoFixWin11BitBlt }
                    });

                _overlayWindowScheduler.Start(interval);
                _captureTriggerScheduler.Start(interval);
                _started = true;
            }
            catch
            {
                _startFailed = true;
                CleanupFailedStart();
                throw;
            }
            finally
            {
                _starting = false;
            }
        }

        private void CleanupFailedStart()
        {
            TryCleanup("capture scheduler stop", _captureTriggerScheduler.Stop);
            TryCleanup("overlay scheduler stop", _overlayWindowScheduler.Stop);

            var capture = GameCapture;
            GameCapture = null;
            TryCleanup("game capture stop", () => capture?.Stop());
            TryCleanup("game capture dispose", () => capture?.Dispose());
            TryCleanup("clear task manager triggers", GameTaskManager.ClearTriggers);
            _systemInfo = null;
        }

        private void TryCleanup(string operation, Action action)
        {
            try
            {
                action();
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed startup cleanup step: {Operation}", operation);
            }
        }

        public void Stop()
        {
            _captureTriggerScheduler.Stop();
            _overlayWindowScheduler.StopTimer();
            ChatUiHotkeyGuard.Reset();
            GameCapture?.Stop();
            _overlayWindowScheduler.Stop();
        }

        public void StartTimer()
        {
            _overlayWindowScheduler.StartTimer();
            _captureTriggerScheduler.StartTimer();
        }

        public void StopTimer()
        {
            _captureTriggerScheduler.StopTimer();
            _overlayWindowScheduler.StopTimer();

            ChatUiHotkeyGuard.Reset();
        }

        public void Dispose()
        {
            Stop();
            _captureTriggerScheduler.Dispose();
            _overlayWindowScheduler.Dispose();
        }

        public void Tick(object? sender, EventArgs e)
        {
            _captureTriggerScheduler.ProcessCaptureFrame(sender, e);
        }

        private void OnUiTaskStopTick(object? sender, EventArgs e)
        {
            UiTaskStopTickEvent?.Invoke(sender, e);
        }

        public void TakeScreenshot()
        {
            try
            {
                var gameCapture = GameCapture
                    ?? throw new InvalidOperationException("截图器未初始化!");
                new GameScreenshotTask(
                        new WindowsGameScreenshotRuntimePlatform(gameCapture),
                        _logger)
                    .TakeScreenshot();
            }
            catch (Exception e)
            {
                _logger.LogError("截图保存失败: {Message}", e.Message);
                _logger.LogDebug("截图保存失败: {StackTrace}", e.StackTrace);
            }
        }
    }
}
