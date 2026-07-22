#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
macgi_root=${script_dir:h}
configuration=${CONFIGURATION:-Release}
swift_configuration=${(L)configuration}
app_name=${MACGI_APP_NAME:-betterGI-mac.app}
output_root=${MACGI_APP_OUTPUT_ROOT:-${macgi_root}/.build/App}
app=${output_root}/${app_name}
contents=${app}/Contents
executable_name=betterGI-mac
bundle_identifier=${MACGI_BUNDLE_IDENTIFIER:-cn.jac0bshi.bettergi.mac}
short_version=${MACGI_SHORT_VERSION:-0.1.0}
bundle_version=${MACGI_BUNDLE_VERSION:-1}
signing_identity=${EXPANDED_CODE_SIGN_IDENTITY:-}
if [[ -z ${signing_identity} ]]; then
  signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | head -n 1)
fi
signing_identity=${signing_identity:--}

swift build --package-path ${macgi_root} -c ${swift_configuration} --product ${executable_name}
bin_dir=$(swift build --package-path ${macgi_root} -c ${swift_configuration} --show-bin-path)
executable=${bin_dir}/${executable_name}
resource_bundle=${bin_dir}/${executable_name}_MacGI.bundle

if [[ ! -x ${executable} ]]; then
  print -u2 "Swift executable is missing: ${executable}"
  exit 2
fi
if [[ ! -d ${resource_bundle} ]]; then
  print -u2 "SwiftPM resource bundle is missing: ${resource_bundle}"
  exit 3
fi

rm -rf ${app}
mkdir -p ${contents}/MacOS ${contents}/Resources
cp ${executable} ${contents}/MacOS/${executable_name}
cp -R ${resource_bundle} ${contents}/Resources/${resource_bundle:t}
${script_dir}/stage-game-task-assets.sh \
  ${contents}/Resources/${resource_bundle:t}/GameTask

plist=${contents}/Info.plist
plutil -create xml1 ${plist}
/usr/libexec/PlistBuddy -c "Add :CFBundleName string betterGI-mac" ${plist}
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string BetterGI" ${plist}
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${bundle_identifier}" ${plist}
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ${executable_name}" ${plist}
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" ${plist}
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${short_version}" ${plist}
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${bundle_version}" ${plist}
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" ${plist}
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" ${plist}
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" ${plist}

TARGET_BUILD_DIR=${output_root} \
WRAPPER_NAME=${app_name} \
EXPANDED_CODE_SIGN_IDENTITY=${signing_identity} \
${script_dir}/package-bettergi-core.sh

sign_options=(--force --timestamp=none --sign ${signing_identity})
if [[ ${signing_identity} != "-" ]]; then
  sign_options+=(--options runtime)
fi
codesign ${sign_options[@]} ${contents}/MacOS/${executable_name}
codesign ${sign_options[@]} ${app}
codesign --verify --deep --strict --verbose=2 ${app}

smoke_root=$(mktemp -d ${TMPDIR:-/tmp}/bettergi-recognition-smoke.XXXXXX)
trap 'rm -rf ${smoke_root}' EXIT
cp -R ${contents}/Resources/${resource_bundle:t}/GameTask ${smoke_root}/GameTask
${contents}/Resources/BetterGICore/BetterGenshinImpact.Core.Host \
  --recognition-smoke --runtime-root ${smoke_root}

print "Signing identity: ${signing_identity}"
print "betterGI-mac app packaged at ${app}"
