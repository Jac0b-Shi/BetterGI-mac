#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
idle_seconds=${BETTERGI_WINE_BRIDGE_IDLE_TEST_SECONDS:-61}

BETTERGI_WINE_BRIDGE_IDLE_TEST_SECONDS=${idle_seconds} \
  "${repo_root}/scripts/verify-wine-bridge.sh"
