#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
exec "${repo_root}/scripts/verify-core-extraction.sh"
