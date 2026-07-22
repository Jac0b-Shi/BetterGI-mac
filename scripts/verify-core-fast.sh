#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
configuration=${CONFIGURATION:-Debug}
suite=${1:-all}
fast_project=${repo_root}/Test/BetterGenshinImpact.Core.Host.Fast.Verification/BetterGenshinImpact.Core.Host.Fast.Verification.csproj
framework_project=${repo_root}/Test/BetterGenshinImpact.Verification.Framework/BetterGenshinImpact.Verification.Framework.csproj

dotnet build "${repo_root}/BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj" \
  -c "${configuration}" --no-restore
dotnet build "${repo_root}/BetterGenshinImpact.Core.Host/BetterGenshinImpact.Core.Host.csproj" \
  -c "${configuration}" --no-restore
dotnet build "${framework_project}" -c "${configuration}" --no-restore
dotnet build "${fast_project}" -c "${configuration}" --no-restore --no-dependencies
dotnet run --project "${fast_project}" -c "${configuration}" --no-build -- --suite "${suite}"
