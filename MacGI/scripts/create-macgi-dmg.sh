#!/bin/zsh
set -euo pipefail

if (( $# < 2 || $# > 3 )); then
  print -u2 "Usage: $0 <app-bundle> <output-dmg> [volume-name]"
  exit 2
fi

app=${1:A}
output=${2:A}
volume_name=${3:-BetterGI}

if [[ ! -d ${app} || ${app:e} != app ]]; then
  print -u2 "App bundle not found: ${app}"
  exit 3
fi

mkdir -p ${output:h}
staging=$(mktemp -d ${TMPDIR:-/tmp}/bettergi-dmg.XXXXXX)
trap 'rm -rf ${staging}' EXIT

ditto ${app} ${staging}/${app:t}
ln -s /Applications ${staging}/Applications
rm -f ${output}
hdiutil create \
  -volname ${volume_name} \
  -srcfolder ${staging} \
  -ov \
  -format UDZO \
  ${output}

print "BetterGI disk image created at ${output}"
