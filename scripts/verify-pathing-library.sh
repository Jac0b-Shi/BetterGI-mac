#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
configuration=${CONFIGURATION:-Debug}
runtime_root=${1:-${HOME}/Library/Application Support/betterGI-mac}
project=${repo_root}/Test/BetterGenshinImpact.Pathing.Verification/BetterGenshinImpact.Pathing.Verification.csproj

dotnet build "${repo_root}/BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj" \
  -c "${configuration}" --no-restore
dotnet build "${project}" -c "${configuration}" --no-restore --no-dependencies
dotnet run --project "${project}" -c "${configuration}" --no-build -- \
  --runtime-root "${runtime_root}"
