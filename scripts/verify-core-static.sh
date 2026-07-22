#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
"${repo_root}/scripts/verify-core-extraction.sh"

cd "${repo_root}"
rg -q 'ActionFactory\.CanExecuteAfterWaypoint\(waypoint\.Action\)' \
  BetterGenshinImpact/GameTask/AutoPathing/PathExecutor.cs
rg -q 'PathExecutor\.SupportsAction\(waypoint\.Action\)' \
  Test/BetterGenshinImpact.Pathing.Verification/Program.cs
