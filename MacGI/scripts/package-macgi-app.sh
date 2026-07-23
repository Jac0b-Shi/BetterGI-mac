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
default_bundle_identifier=cn.jac0bshi.bettergi.mac
if [[ ${MACGI_ALLOW_ADHOC_SIGNING:-0} == 1 && -z ${MACGI_BUNDLE_IDENTIFIER:-} ]]; then
  default_bundle_identifier=${default_bundle_identifier}.adhoc
fi
bundle_identifier=${MACGI_BUNDLE_IDENTIFIER:-${default_bundle_identifier}}
short_version=${MACGI_SHORT_VERSION:-0.1.0}
bundle_version=${MACGI_BUNDLE_VERSION:-1}
signing_identity=${MACGI_SIGNING_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY:-}}
if [[ ${MACGI_ALLOW_ADHOC_SIGNING:-0} == 1 ]]; then
  signing_identity=-
elif [[ -z ${signing_identity} || ${signing_identity} == "-" ]]; then
  signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | head -n 1)
fi
if [[ -z ${signing_identity} || ${signing_identity} == "-" ]]; then
  print -u2 "Apple Development signing identity is required for local TCC-stable builds."
  print -u2 "Set MACGI_ALLOW_ADHOC_SIGNING=1 only for CI packaging smoke tests."
  exit 4
fi

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
bundled_resources=${contents}/Resources/${resource_bundle:t}/Resources
${script_dir}/stage-game-task-assets.sh \
  ${bundled_resources}/GameTask

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
/usr/libexec/PlistBuddy -c "Add :NSScreenCaptureUsageDescription string BetterGI 需要读取原神窗口画面，以执行图像识别和自动化任务。" ${plist}

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
if [[ ${signing_identity} != "-" ]]; then
  launch_services_register=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  ${launch_services_register} -f ${app}
fi

smoke_root=$(mktemp -d ${TMPDIR:-/tmp}/bettergi-recognition-smoke.XXXXXX)
trap 'rm -rf ${smoke_root}' EXIT
cp -R ${bundled_resources}/GameTask ${smoke_root}/GameTask
${contents}/Resources/BetterGICore/BetterGenshinImpact.Core.Host \
  --recognition-smoke --runtime-root ${smoke_root}

print "Signing identity: ${signing_identity}"
print "Bundle identifier: ${bundle_identifier}"
print "betterGI-mac app packaged at ${app}"
