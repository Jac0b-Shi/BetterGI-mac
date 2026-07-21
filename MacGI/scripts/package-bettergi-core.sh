#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
macgi_root=${script_dir:h}
bettergi_root=${BETTERGI_SOURCE_ROOT:-${macgi_root:h}}
project=${bettergi_root}/BetterGenshinImpact.Core.Host/BetterGenshinImpact.Core.Host.csproj
configuration=${CONFIGURATION:-Release}
rid=${BETTERGI_CORE_RID:-osx-arm64}
publish_dir=${BUILT_PRODUCTS_DIR:-${macgi_root}/.build}/BetterGICore

if [[ ! -f ${project} ]]; then
  print -u2 "BetterGI Core Host project not found: ${project}"
  exit 2
fi

rm -rf ${publish_dir}
dotnet publish ${project} \
  -c ${configuration} \
  -r ${rid} \
  --self-contained true \
  -p:PublishSingleFile=false \
  -o ${publish_dir}

host=${publish_dir}/BetterGenshinImpact.Core.Host
if [[ ! -x ${host} ]]; then
  print -u2 "Published Core Host executable is missing: ${host}"
  exit 3
fi

${host} --dependency-smoke

if [[ -n ${TARGET_BUILD_DIR:-} && -n ${WRAPPER_NAME:-} ]]; then
  destination=${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Contents/Resources/BetterGICore
  rm -rf ${destination}
  mkdir -p ${destination:h}
  cp -R ${publish_dir} ${destination}
  if [[ -n ${EXPANDED_CODE_SIGN_IDENTITY:-} ]]; then
    sign_options=(--force --timestamp=none --sign ${EXPANDED_CODE_SIGN_IDENTITY})
    if [[ ${EXPANDED_CODE_SIGN_IDENTITY} != "-" ]]; then
      sign_options+=(--options runtime)
    fi
    while IFS= read -r binary; do
      if file ${binary} | grep -q 'Mach-O'; then
        codesign ${sign_options[@]} ${binary}
        codesign --verify --strict --verbose=2 ${binary}
      fi
    done < <(find ${destination} -type f | sort)
  fi
fi

print "BetterGI Core Host published at ${publish_dir}"
