#!/bin/sh
# Builds dist/VibeBattery.app with Xcode (so the Shortcuts actions' metadata ships) and signs it.
# Shortcuts only lists actions from apps signed with a team: set VB_SIGN_IDENTITY, or the first
# "Apple Development" identity in the keychain is used. Without one the build is ad-hoc.
set -eu
cd "$(dirname "$0")/.."
VB_OUTPUT_DIR=${VB_OUTPUT_DIR:-"$PWD/dist"}
VB_DERIVED="$PWD/.build/xcode"
VB_SIGN_IDENTITY=${VB_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: .*\)"$/\1/p' | head -1)}
VB_SIGN_IDENTITY=${VB_SIGN_IDENTITY:--}
mkdir -p "$VB_DERIVED"
xcodebuild -project VibeBattery.xcodeproj -scheme VibeBatteryApp -configuration Release -derivedDataPath "$VB_DERIVED" build >"$VB_DERIVED/build.log" 2>&1 || { tail -40 "$VB_DERIVED/build.log";exit 1; }
# Sign outside the output folder: a synced folder (iCloud Documents) can re-add
# Finder metadata mid-build, which strict signature checks reject.
VB_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/vibebattery-build.XXXXXX")
trap 'rm -rf "$VB_STAGE"' EXIT
VB_APP="$VB_STAGE/VibeBattery.app"
ditto --norsrc --noextattr "$VB_DERIVED/Build/Products/Release/VibeBattery.app" "$VB_APP"
codesign --force --sign "$VB_SIGN_IDENTITY" "$VB_APP/Contents/MacOS/vbctl"
# The helper only trusts its own identifier; Xcode signs tools with a generated one.
codesign --force --sign "$VB_SIGN_IDENTITY" --identifier io.github.y-minion.vibebattery.helper "$VB_APP/Contents/MacOS/VBChargeHelper"
codesign --force --sign "$VB_SIGN_IDENTITY" "$VB_APP"
codesign --verify --strict "$VB_APP"
for f in Contents/Resources/Metadata.appintents Contents/Resources/install-helper.sh Contents/Resources/uninstall-helper.sh Contents/MacOS/vbctl Contents/MacOS/VBChargeHelper; do
    [ -e "$VB_APP/$f" ] || { echo "빌드 결과에 $f 가 없습니다." >&2;exit 1; }
done
codesign -dv "$VB_APP/Contents/MacOS/VBChargeHelper" 2>&1 | grep -q '^Identifier=io.github.y-minion.vibebattery.helper$' || { echo "헬퍼 서명 식별자가 다릅니다." >&2;exit 1; }
mkdir -p "$VB_OUTPUT_DIR"
rm -rf "$VB_OUTPUT_DIR/VibeBattery.app"
ditto --norsrc --noextattr "$VB_APP" "$VB_OUTPUT_DIR/VibeBattery.app"
ditto -c -k --norsrc --noextattr --keepParent "$VB_APP" "$VB_OUTPUT_DIR/VibeBattery.zip"
[ "$VB_SIGN_IDENTITY" = - ] && echo "임시 서명으로 빌드했습니다. 단축어 앱에는 동작이 보이지 않습니다." >&2
printf '%s\n' "$VB_OUTPUT_DIR/VibeBattery.app"
