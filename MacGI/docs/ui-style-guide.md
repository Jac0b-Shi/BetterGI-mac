# betterGI-mac UI Style Guide

## Direction

betterGI-mac should feel like a BetterGI-style game assistant console on macOS, not like a native macOS preferences pane.

## Layout

- Left navigation is always visible.
- Header bar always shows current running state and game-window state.
- Main content uses dense cards with title, helper text, and right-aligned controls.
- Logs use monospaced text and dark console surfaces.
- HUD is a persistent bottom-right status surface, not a notification.

## Components

- `BGINavSidebar`: primary navigation.
- `BGIHeaderBar`: title, state badges, start/pause action.
- `BGISectionCard`: card container.
- `BGIOriginalCard`: BetterGI-style card/expander with icon, header action, optional expanded details, and source-compatible row density.
- `BGIWorkflowShell`: workbench layout for pages that need a left configuration group and a right task/configuration surface.
- `BGIGroupSidebar`: fixed-width configuration group list used by one-dragon and scheduler-like pages.
- `BGIDataTable`: static/mock table layout for ListView/GridView style pages until real models are connected.
- `BGIStatusBadge`: compact state label.
- `BGIFeatureToggle`: feature row with icon, description, badge, and switch.
- `BGILogConsole`: scrollable log list.
- `SettingRow`: compact setting row.

## Visual Tokens

Defined in `Sources/MacGI/Design/DesignTokens.swift`:

- `BGIColors`
- `BGIRadius`
- `BGISpacing`
- `BGIFonts`

The default theme is dark, with deep neutral backgrounds, blue accent, green success, amber warning, and red error states.

## Interaction Rules

- All visible runtime state must come from `AppState`.
- View files should not contain capture, input, or Rust business logic.
- Mock actions should add logs so both main window and HUD visibly update.
- HUD controls are controlled from the main UI or menu bar; the HUD itself is mouse passthrough.
- Screenshots are not exhaustive. When a page has missing details, inspect upstream XAML/ViewModel/config files and mirror the page hierarchy before inventing new macOS-native structure.
- Workflow pages such as 一条龙, 调度器, JS 脚本, 地图追踪, and 录制回放 should keep BetterGI's group/sidebar, command bar, table/list, and right-side configuration pattern.
