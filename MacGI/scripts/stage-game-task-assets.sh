#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
macgi_root=${script_dir:h}
bettergi_root=${BETTERGI_SOURCE_ROOT:-${macgi_root:h}}
source_root=${bettergi_root}/BetterGenshinImpact/GameTask
manifest=${MACGI_GAME_TASK_MANIFEST:-${macgi_root}/Resources/game-task-assets.manifest}
destination=${1:?usage: stage-game-task-assets.sh <destination>}

[[ -d ${source_root} ]] || { print -u2 "BetterGI GameTask source is missing: ${source_root}"; exit 2; }
[[ -f ${manifest} ]] || { print -u2 "GameTask asset manifest is missing: ${manifest}"; exit 3; }

rm -rf ${destination}
mkdir -p ${destination}

while IFS= read -r entry; do
  [[ -z ${entry} || ${entry} == \#* ]] && continue
  task_root=${source_root}/${entry}
  [[ -d ${task_root} ]] || { print -u2 "Manifest task is missing: ${entry}"; exit 4; }
  assets_found=false
  while IFS= read -r assets; do
    assets_found=true
    relative=${assets#${source_root}/}
    mkdir -p ${destination}/${relative:h}
    cp -R ${assets} ${destination}/${relative:h}/
  done < <(find ${task_root} -type d -name Assets -prune | sort)
  ${assets_found} || { print -u2 "Manifest task has no Assets directory: ${entry}"; exit 5; }
done < ${manifest}

count=$(find ${destination} -type f | wc -l | tr -d ' ')
(( count > 0 )) || { print -u2 "No GameTask assets were staged"; exit 6; }
while IFS= read -r staged_file; do
  relative=${staged_file#${destination}/}
  cmp -s ${source_root}/${relative} ${staged_file} \
    || { print -u2 "Staged asset differs from canonical source: ${relative}"; exit 7; }
done < <(find ${destination} -type f | sort)
print "Staged ${count} canonical GameTask assets at ${destination}"
