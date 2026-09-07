#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
"${repo_root}/scripts/verify-core-extraction.sh"

cd "${repo_root}"
rg -q 'ActionFactory\.CanExecuteAfterWaypoint\(waypoint\.Action\)' \
  BetterGenshinImpact/GameTask/AutoPathing/PathExecutor.cs
rg -q 'PathExecutor\.SupportsAction\(waypoint\.Action\)' \
  Test/BetterGenshinImpact.Pathing.Verification/Program.cs
rg -q '"OverlayMetricsDisplayHotkey"' \
  BetterGenshinImpact.Core.Host/Runtime/HotKeySettingsCatalog.cs
rg -q '"overlay\.metrics\.toggle"' \
  BetterGenshinImpact.Core.Host/Runtime/HotKeySettingsCatalog.cs
rg -q 'case "overlay\.metrics\.toggle":' \
  MacGI/Sources/MacGI/App/AppState.swift
rg -q 'case mouseMoveRelative\(deltaX: CGFloat, deltaY: CGFloat\)' \
  MacGI/Sources/MacGI/Model/PlatformInputModels.swift
rg -q 'return \.mouseMoveRelative\(deltaX: x, deltaY: y\)' \
  MacGI/Sources/MacGI/Runtime/BetterGICorePlatformAdapter.swift
rg -q '\.mouseEventDeltaX' \
  MacGI/Sources/MacGI/Runtime/CGEventInputDispatcher.swift
rg -q '\.mouseEventDeltaY' \
  MacGI/Sources/MacGI/Runtime/CGEventInputDispatcher.swift

# Desktop Clone remains a Windows-only WPF feature. macOS owns background
# capture/input/session cleanup through the Wine + Quartz bridge and must never
# acquire ChildSession/RDP contracts or native dependencies.
if rg -n 'ChildSession|RdpActiveXHost|AxMSTSCLib|MSTSCLib' \
  BetterGenshinImpact.Core BetterGenshinImpact.Core.Host \
  MacGI/Package.swift MacGI/Sources MacGI/Tests MacGI/scripts \
  --glob '!**/bin/**' --glob '!**/obj/**'; then
  print -u2 'Desktop Clone/RDP dependency leaked into the macOS product boundary.'
  exit 1
fi
rg -q 'class ChildSessionService' \
  BetterGenshinImpact/Service/ChildSession/ChildSessionService.cs
rg -q 'WineBridgeSessionInvalidationMode' \
  MacGI/Sources/MacGI/Runtime/WineBridgeInputDispatcher.swift
rg -q 'background' MacGI/Sources/MacGI/Runtime/BetterGICorePlatformAdapter.swift
