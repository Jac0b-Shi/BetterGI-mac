#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
area=${1:-fast}
configuration=${CONFIGURATION:-Debug}
core_verifier=${repo_root}/Test/BetterGenshinImpact.Core.Verification/BetterGenshinImpact.Core.Verification.csproj

run_core_suite() {
  dotnet build "${repo_root}/BetterGenshinImpact.Core/BetterGenshinImpact.Core.csproj" \
    -c "${configuration}" --no-restore
  dotnet build "${core_verifier}" -c "${configuration}" --no-restore --no-dependencies
  dotnet run --project "${core_verifier}" -c "${configuration}" --no-build -- \
    --suite "$1"
}

case "${area}" in
  fast)
    "${repo_root}/scripts/verify-core-fast.sh" all
    ;;
  trigger-settings|solo-settings|script-group-editing|script-repository|runtime-cancellation)
    "${repo_root}/scripts/verify-core-fast.sh" "${area}"
    ;;
  pathing)
    "${repo_root}/scripts/verify-pathing-library.sh"
    ;;
  static)
    "${repo_root}/scripts/verify-core-static.sh"
    ;;
  contracts|artifacts|models|recognition)
    run_core_suite "${area}"
    ;;
  full)
    "${repo_root}/scripts/verify-core-full.sh"
    ;;
  *)
    print -u2 -- "Unknown verification area: ${area}"
    print -u2 -- "Expected: fast, trigger-settings, solo-settings, script-group-editing, script-repository, runtime-cancellation, pathing, static, contracts, artifacts, models, recognition, or full"
    exit 2
    ;;
esac
