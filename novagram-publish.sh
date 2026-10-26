#!/bin/bash
# Archive Novagram for the Mac App Store and check the result. Never uploads anything.
#
#   ./novagram-publish.sh                      preflight checks, archive, archive checks
#   ./novagram-publish.sh --preflight          build-setting checks only (no build)
#   ./novagram-publish.sh --check <path.xcarchive>   checks on an existing archive only
#
# Env: NOVAGRAM_DD (DerivedData, default /tmp/tgmac13-dd-publish), NOVAGRAM_LOG (default /tmp/novagram13-publish.log).
#
# APP_STORE goes on the xcodebuild command line on purpose: only command-line build settings reach
# the Swift packages, the xcconfig flag reaches the app target only (see AGENTS.md).

set -u
set -o pipefail

cd "$(dirname "$0")" || exit 1

WORKSPACE="Telegram-Mac.xcworkspace"
SCHEME="Release"
CONFIGURATION="Release"
TEAM_ID="ZDBP5RSRZF"
BUNDLE_ID="uz.fenixuz.app"
SANDBOX_ENTITLEMENTS="Telegram-Mac/Telegram-Sandbox.entitlements"
DD="${NOVAGRAM_DD:-/tmp/tgmac13-dd-publish}"
LOG="${NOVAGRAM_LOG:-/tmp/novagram13-publish.log}"
APP_STORE_CONDITIONS='$(inherited) APP_STORE'

FAILURES=0

pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; FAILURES=$((FAILURES + 1)); }
warn() { echo "  warn  $1"; }

setting() {
    # $1 = settings dump, $2 = name; first value in the Telegram target section
    awk -v name="$2" '
        /^Build settings for action .* and target / { inTarget = ($NF == "Telegram:") }
        inTarget && $1 == name && $2 == "=" { sub(/^[^=]*= ?/, ""); print; exit }
    ' "$1"
}

preflight() {
    echo "Preflight: Release build settings (target Telegram)"
    local dump
    dump="$(mktemp -t novagram-publish-settings)"
    if ! xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
        -derivedDataPath "$DD" -showBuildSettings \
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$APP_STORE_CONDITIONS" > "$dump" 2>/dev/null; then
        fail "xcodebuild -showBuildSettings failed"
        rm -f "$dump"
        return
    fi

    local value
    value="$(setting "$dump" CODE_SIGN_ENTITLEMENTS)"
    [ "$value" = "$SANDBOX_ENTITLEMENTS" ] && pass "entitlements: $value" || fail "entitlements: '$value' (want $SANDBOX_ENTITLEMENTS)"
    value="$(setting "$dump" DEVELOPMENT_TEAM)"
    [ "$value" = "$TEAM_ID" ] && pass "team: $value" || fail "team: '$value' (want $TEAM_ID)"
    value="$(setting "$dump" PRODUCT_BUNDLE_IDENTIFIER)"
    [ "$value" = "$BUNDLE_ID" ] && pass "bundle id: $value" || fail "bundle id: '$value' (want $BUNDLE_ID)"
    value="$(setting "$dump" SWIFT_ACTIVE_COMPILATION_CONDITIONS)"
    case " $value " in *" APP_STORE "*) pass "Swift conditions: $value" ;; *) fail "Swift conditions: '$value' (APP_STORE missing)" ;; esac
    value="$(setting "$dump" OTHER_SWIFT_FLAGS)"
    case "$value" in *APP_STORE*) pass "app Swift flags: $value" ;; *) fail "app Swift flags: '$value' (APP_STORE missing)" ;; esac
    value="$(setting "$dump" OTHER_LDFLAGS)"
    case "$value" in *-dead_strip_dylibs*) pass "linker flags: $value" ;; *) fail "linker flags: '$value' (-dead_strip_dylibs missing)" ;; esac
    value="$(setting "$dump" SFEED_URL)"
    case "$value" in *127.0.0.1*) pass "Sparkle feed is the dead local URL" ;; *) fail "Sparkle feed: '$value'" ;; esac
    value="$(setting "$dump" ENABLE_USER_SCRIPT_SANDBOXING)"
    [ "$value" = "NO" ] && pass "user script sandboxing: NO (strip phase may edit the bundle)" || fail "user script sandboxing: '$value' (the Sparkle strip phase cannot write the bundle)"

    if grep -q 'CODE_SIGN_IDENTITY = "";' Telegram.xcodeproj/project.pbxproj; then
        fail 'empty CODE_SIGN_IDENTITY in project.pbxproj (ad-hoc archive, "No Team Found")'
    else
        pass "no empty CODE_SIGN_IDENTITY"
    fi
    if grep -q "Novagram: strip Sparkle (App Store)" Telegram.xcodeproj/project.pbxproj; then
        pass "Sparkle strip build phase present"
    else
        fail "Sparkle strip build phase missing"
    fi

    MARKETING_VERSION="$(setting "$dump" MARKETING_VERSION)"
    BUILD_NUMBER="$(setting "$dump" CURRENT_PROJECT_VERSION)"
    rm -f "$dump"
}

check_archive() {
    local archive="$1"
    local app
    app="$(find "$archive/Products/Applications" -maxdepth 1 -name "*.app" | head -1)"
    echo "Archive checks: $archive"
    if [ -z "$app" ] || [ ! -d "$app" ]; then
        fail "no .app inside the archive"
        return
    fi
    local plist="$app/Contents/Info.plist"
    local binary="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null)"

    local value
    value="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null)"
    [ "$value" = "$BUNDLE_ID" ] && pass "bundle id: $value" || fail "bundle id: '$value' (want $BUNDLE_ID)"

    for key in SUFeedURL SUPublicDSAKeyFile SUPublicEDKey SUEnableAutomaticChecks; do
        if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
            fail "Info.plist still has $key"
        else
            pass "Info.plist has no $key"
        fi
    done

    if ls "$app/Contents/Frameworks/" 2>/dev/null | grep -qiE "sparkle|appcenter"; then
        fail "Sparkle/AppCenter embedded in Contents/Frameworks"
    else
        pass "no Sparkle/AppCenter in Contents/Frameworks"
    fi
    if otool -L "$binary" 2>/dev/null | grep -qi sparkle; then
        fail "main binary still links Sparkle (otool -L)"
    else
        pass "main binary has no Sparkle load command"
    fi

    local entitlements
    entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null)"
    if echo "$entitlements" | grep -A1 "com.apple.security.app-sandbox" | grep -q "<true/>"; then
        pass "app sandbox: true"
    else
        fail "app sandbox is not true"
    fi
    if echo "$entitlements" | grep -q "com.apple.security.get-task-allow"; then
        fail "get-task-allow present"
    else
        pass "no get-task-allow"
    fi

    local signature
    signature="$(codesign -dvvv "$app" 2>&1)"
    if echo "$signature" | grep -q "TeamIdentifier=$TEAM_ID"; then
        pass "TeamIdentifier=$TEAM_ID"
    else
        fail "TeamIdentifier is not $TEAM_ID"
    fi
    value="$(echo "$signature" | grep -m1 "^Authority=" | cut -d= -f2-)"
    case "$value" in
        "Apple Distribution"*|"3rd Party Mac Developer Application"*) pass "signed by: $value" ;;
        *) warn "signed by: '$value' (Organizer re-signs with Apple Distribution on export)" ;;
    esac

    if [ -f "$app/Contents/Resources/PrivacyInfo.xcprivacy" ]; then
        pass "PrivacyInfo.xcprivacy present"
    else
        fail "PrivacyInfo.xcprivacy missing"
    fi

    local appex="$app/Contents/PlugIns/TelegramShare.appex"
    if [ -d "$appex" ]; then
        if codesign -d --entitlements - --xml "$appex" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null | grep -A1 "com.apple.security.app-sandbox" | grep -q "<true/>"; then
            pass "share extension sandbox: true"
        else
            fail "share extension sandbox is not true"
        fi
    fi
}

finish() {
    echo
    if [ "$FAILURES" -eq 0 ]; then
        echo "ALL CHECKS PASSED"
        exit 0
    fi
    echo "$FAILURES CHECK(S) FAILED"
    exit 1
}

case "${1:-}" in
    --preflight)
        preflight
        finish
        ;;
    --check)
        [ -n "${2:-}" ] || { echo "usage: $0 --check <path.xcarchive>"; exit 2; }
        check_archive "$2"
        finish
        ;;
    "")
        ;;
    *)
        echo "usage: $0 [--preflight | --check <path.xcarchive>]"
        exit 2
        ;;
esac

preflight
if [ "$FAILURES" -ne 0 ]; then
    echo "Preflight failed, not archiving."
    finish
fi

ARCHIVE="build/archives/Novagram-${MARKETING_VERSION:-unknown}-${BUILD_NUMBER:-unknown}.xcarchive"
mkdir -p build/archives
echo
echo "Archiving $ARCHIVE $(date +%H:%M:%S) (log: $LOG)"
if xcodebuild archive -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -derivedDataPath "$DD" -archivePath "$ARCHIVE" \
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$APP_STORE_CONDITIONS" > "$LOG" 2>&1; then
    echo "ARCHIVE SUCCEEDED ($(date +%H:%M:%S))"
else
    echo "ARCHIVE FAILED - errors:"
    grep -E "error:" "$LOG" | sort -u | head -10
    exit 1
fi

echo
check_archive "$ARCHIVE"
echo
echo "Next (manual): Xcode Organizer > Distribute App > App Store Connect. This script uploads nothing."
finish
