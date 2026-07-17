# BetterGI UI Inventory

This inventory is based on the referenced BetterGI repository at `/Volumes/Aquarius/CodeProjects/better-genshin-impact`.

## Source Files Read

- `BetterGenshinImpact/View/MainWindow.xaml`
- `BetterGenshinImpact/View/MaskWindow.xaml`
- `BetterGenshinImpact/View/Pages/HomePage.xaml`
- `BetterGenshinImpact/View/Pages/TriggerSettingsPage.xaml`
- `BetterGenshinImpact/View/Pages/TaskSettingsPage.xaml`
- `BetterGenshinImpact/View/Pages/OneDragonFlowPage.xaml`
- `BetterGenshinImpact/View/Pages/ScriptControlPage.xaml`
- `BetterGenshinImpact/View/Pages/JsListPage.xaml`
- `BetterGenshinImpact/View/Pages/MapPathingPage.xaml`
- `BetterGenshinImpact/View/Pages/KeyMouseRecordPage.xaml`
- `BetterGenshinImpact/View/Pages/MacroSettingsPage.xaml`
- `BetterGenshinImpact/View/Pages/HotkeyPage.xaml`
- `BetterGenshinImpact/View/Pages/NotificationSettingsPage.xaml`
- `BetterGenshinImpact/View/Pages/CommonSettingsPage.xaml`
- `BetterGenshinImpact/ViewModel/MainWindowViewModel.cs`
- `BetterGenshinImpact/ViewModel/MaskWindowViewModel.cs`
- `BetterGenshinImpact/Core/Config/MaskWindowConfig.cs`
- `BetterGenshinImpact/Core/Config/OverlayMetricItem.cs`

## Main Window Structure

BetterGI uses a WPF-UI `FluentWindow` with content extended into the title bar. The main layout is:

- A title bar with app title, logo, feed button, theme/backdrop switch, and hide-to-tray command.
- A left `NavigationView` pane with primary pages and nested automation entries.
- A central page frame rendered from navigation targets.
- A tray icon with update and exit actions.

Observed primary navigation:

- 启动
- 实时触发
- 独立任务
- 一条龙
- 全自动
- 辅助操控
- 快捷键
- 通知
- 设置

## Page Patterns

BetterGI pages use repeated card controls:

- `CardExpander` for major modules with expandable configuration.
- `CardControl` for compact setting rows.
- Two-line setting descriptions: title plus secondary helper text.
- Right-aligned controls such as toggle switches, buttons, combo boxes, number boxes, and text boxes.
- Strong task entry points such as start/stop two-state buttons.

Important page groups:

- Home: banner, screenshot/task dispatcher start card, capture mode, trigger interval, inference device.
- Trigger settings: auto pickup, auto dialog, auto interaction features with OCR, blacklist/whitelist, key settings.
- Task settings: independent task cards with start/stop buttons and per-task configuration.
- One Dragon: task list, configuration selector, enabled task rows, daily/weekly domain settings, boss, ley line, reward, Serenitea Pot, and finish action settings.
- Scheduler: configuration groups, continuous execution commands, add menu for JS/pathing/key-mouse/Shell tasks, task table, context commands.
- JS scripts: script directory/repository actions and script table with directory, name, version, execute/open/refresh/delete commands.
- Map tracking: task directory/repository actions, settings/dev tools, pathing task table, and future overlay point/path display.
- Key mouse record: script directory/repository actions, start/stop recording commands, script list with play/edit/delete.
- Macro settings: per-character one-key macro, Neuvillette spin macro, artifact enhancement, one-key buy, teapot, confirm/cancel, hold-space/F repeat toggles.
- Hotkey: tree/table of function, hotkey type, and configured shortcut.
- Notification: many provider cards including global, Webhook, WebSocket, native notification, Feishu, OneBot, WeCom, Email, Bark, Telegram, DingTalk, Discord, ServerChan.
- Common settings: language, overlay/mask window, log box, status display, overlay layout editing, metrics, screenshot saving, script update, teleport, statue healing, other/OCR/update/about.

## Overlay / HUD Structure

`MaskWindow.xaml` is a transparent, topmost, non-taskbar overlay window. It contains:

- A transparent root window with no chrome.
- Status list overlay showing enabled realtime features.
- Log text box overlay using monospaced text and low-opacity foreground.
- Metrics overlay with fixed-width metric items.
- Optional overlay layout edit mode with large centered help text.
- Direction markers, UID cover, map points, mini-map points, and loading overlays.

`MaskWindowViewModel` initializes status items for pickup, dialog, hangout, fishing, and teleport. It also maps overlay metric items such as game FPS, processing cost, capture cost, trigger cost, skipped ticks, GPU, CPU, and memory.

## betterGI-mac Mapping

| BetterGI UI Element | betterGI-mac SwiftUI Equivalent |
| --- | --- |
| WPF-UI `FluentWindow` | SwiftUI window with custom dark shell |
| `NavigationView` left pane | `BGINavSidebar` |
| Title bar command buttons | `BGIHeaderBar` plus menu bar commands |
| `CardExpander` / `CardControl` | `BGIOriginalCard`, `BGISectionCard`, `BGISettingLine`, and `SettingRow` |
| Two-state start/stop button | AppState-driven Start/Pause button |
| ToggleSwitch feature controls | `BGIFeatureToggle` |
| ComboBox settings | SwiftUI `Picker` |
| NumberBox/TextBox settings | SwiftUI `Stepper`, `Slider`, `TextField` |
| Configuration group sidebar | `BGIWorkflowShell` plus `BGIGroupSidebar` |
| ListView/GridView task tables | `BGIDataTable` mock tables for future model-backed rows |
| RichTextBox overlay log | `HUDView` log list and `BGILogConsole` |
| Transparent mask window | AppKit `NSPanel` HUD |
| Status list overlay | `HUDView` FGI-font status row for pickup/dialog/hangout/fishing/teleport |
| Overlay metrics | `HUDView` three-column metric grid matching `OverlayMetricItem` order |
| UID cover / directions / recognition boxes | `HUDView` mock overlay elements controlled by `AppState` |
| Map points / route overlay | `HUDView` mock `OverlayMapPoint` path and labels, to be replaced by real map-mask data |
| Tray icon menu | SwiftUI `MenuBarExtra` |

## First Prototype Scope

betterGI-mac intentionally does not port WPF/XAML/WinForms code. The first prototype reproduces the UI hierarchy, dark tool-console style, settings density, feature toggles, log surface, and overlay behavior using SwiftUI and AppKit.

Screenshots are only visual references. Detailed settings and nested page structure should be taken from the upstream XAML/ViewModel/config files above, because the screenshot set does not cover every option.
