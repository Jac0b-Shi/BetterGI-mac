#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
configuration=${CONFIGURATION:-Release}
core_solution=${repo_root}/BetterGenshinImpact.Core.sln
core_verifier=${repo_root}/Test/BetterGenshinImpact.Core.Verification/BetterGenshinImpact.Core.Verification.csproj
host_verifier=${repo_root}/Test/BetterGenshinImpact.Core.Host.Verification/BetterGenshinImpact.Core.Host.Verification.csproj
real_user_verifier=${repo_root}/Test/BetterGenshinImpact.RealUser.Verification/BetterGenshinImpact.RealUser.Verification.csproj

dotnet build "${core_solution}" -c "${configuration}" --no-restore

dotnet run --project "${core_verifier}" -c "${configuration}" --no-build
dotnet run --project "${host_verifier}" -c "${configuration}" --no-build
dotnet run --project "${real_user_verifier}" -c "${configuration}" --no-build

"${repo_root}/scripts/verify-core-extraction.sh"
