#!/bin/bash
# novagram-local.sh - keep the local-only changes out of `git status`:
# the Xcode 27 changes (scripts/xcode27.sh apply + the MTProtoEngine deployment target),
# .claude/settings.local.json and the work trees of the submodules (TelegramCore fork patches, Xcode user data).
#
#   scripts/novagram-local.sh hide    hide them; a file with any change besides the Xcode 27 one stays visible
#   scripts/novagram-local.sh show    show them again; run it before staging one of these files
#   scripts/novagram-local.sh check   fail if a hidden file has other changes (run by .git/hooks/pre-commit)
#
# The files stay changed on disk, git only stops reporting them
# (git update-index --skip-worktree, git config submodule.<name>.ignore dirty).

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PBXPROJ=(
    Telegram.xcodeproj/project.pbxproj
    submodules/CodeSyntax/CodeSyntax/CodeSyntax.xcodeproj/project.pbxproj
    submodules/RLottie_Xcode/RLottie_Xcode.xcodeproj/project.pbxproj
    core-xprojects/OpenH264/OpenH264.xcodeproj/project.pbxproj
    core-xprojects/openssl/OpenSSLEncryption.xcodeproj/project.pbxproj
    core-xprojects/libopus/libopus.xcodeproj/project.pbxproj
    core-xprojects/libvpx/libvpx.xcodeproj/project.pbxproj
    core-xprojects/Mozjpeg/Mozjpeg.xcodeproj/project.pbxproj
    core-xprojects/libwebp/libwebp.xcodeproj/project.pbxproj
    core-xprojects/dav1d/dav1d.xcodeproj/project.pbxproj
    core-xprojects/ffmpeg/ffmpeg.xcodeproj/project.pbxproj
    core-xprojects/webrtc/webrtc.xcodeproj/project.pbxproj
    core-xprojects/tde2e/tde2e.xcodeproj/project.pbxproj
    core-xprojects/wallet-engine/WalletEngine.xcodeproj/project.pbxproj
    core-xprojects/mtproto-engine/MTProtoEngine.xcodeproj/project.pbxproj
)
MANIFESTS=(
    packages/CallVideoLayer/Package.swift
    packages/DustLayer/Package.swift
)
SETTINGS=.claude/settings.local.json
HOOK=.git/hooks/pre-commit
HOOK_LINE="scripts/novagram-local.sh check"
# same pattern as scripts/xcode27.sh
SHADER_RESOURCES='(,\s*resources:\s*\[\s*\.copy\("[^"]+\.metal"\)(?:\s*,\s*\.copy\("[^"]+\.metal"\))*\s*\])'

# HEAD version of the file with only the Xcode 27 change made
with_local_change() {
    case "$1" in
        *.pbxproj)
            git show "HEAD:$1" | perl -pe 's/(MACOSX_DEPLOYMENT_TARGET = )(?:10|11)(?:\.\d+)*;/${1}12.0;/g'
            ;;
        *Package.swift)
            git show "HEAD:$1" | SHADER_RESOURCES="$SHADER_RESOURCES" perl -0pe 's/$ENV{SHADER_RESOURCES}//g'
            ;;
    esac
}

# same | local | other
change_kind() {
    if cmp -s <(git show "HEAD:$1") "$1"; then
        echo same
    elif cmp -s <(with_local_change "$1") "$1"; then
        echo local
    else
        echo other
    fi
}

is_hidden() {
    git ls-files -v -- "$1" | grep -q '^S '
}

submodule_names() {
    git config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{ print $1 }' | sed 's/^submodule\.//; s/\.path$//'
}

install_hook() {
    if [ ! -e "$HOOK" ]; then
        printf '#!/bin/sh\n# installed by scripts/novagram-local.sh: stop a commit while a hidden file has other changes\nexec %s\n' "$HOOK_LINE" > "$HOOK"
        chmod +x "$HOOK"
    elif ! grep -qF "$HOOK_LINE" "$HOOK"; then
        echo "note: $HOOK exists, add this line to it: $HOOK_LINE"
    fi
}

hide() {
    local path hidden=0 name
    for path in "${PBXPROJ[@]}" "${MANIFESTS[@]}"; do
        [ -f "$path" ] || continue
        case "$(change_kind "$path")" in
            local)
                git update-index --skip-worktree -- "$path"
                hidden=$((hidden + 1))
                ;;
            other)
                git update-index --no-skip-worktree -- "$path"
                echo "visible: $path has changes besides the Xcode 27 one"
                ;;
            same)
                git update-index --no-skip-worktree -- "$path"
                ;;
        esac
    done
    if [ -f "$SETTINGS" ] && git ls-files --error-unmatch -- "$SETTINGS" > /dev/null 2>&1; then
        git update-index --skip-worktree -- "$SETTINGS"
        hidden=$((hidden + 1))
    fi
    for name in $(submodule_names); do
        git config "submodule.$name.ignore" dirty
    done
    install_hook
    echo "hidden: $hidden files and the submodule work trees (scripts/novagram-local.sh show to see them)"
}

show() {
    local path name
    for path in "${PBXPROJ[@]}" "${MANIFESTS[@]}" "$SETTINGS"; do
        git ls-files --error-unmatch -- "$path" > /dev/null 2>&1 || continue
        git update-index --no-skip-worktree -- "$path"
    done
    for name in $(submodule_names); do
        git config --unset "submodule.$name.ignore" 2> /dev/null
    done
    echo "local changes are visible again (scripts/novagram-local.sh hide to hide them)"
}

check() {
    local path bad=0
    for path in "${PBXPROJ[@]}" "${MANIFESTS[@]}"; do
        [ -f "$path" ] && is_hidden "$path" || continue
        if [ "$(change_kind "$path")" = other ]; then
            echo "hidden but changed: $path" >&2
            bad=1
        fi
    done
    if [ "$bad" = 1 ]; then
        echo "to commit these files: scripts/novagram-local.sh show && scripts/xcode27.sh revert, git add them," >&2
        echo "then scripts/xcode27.sh apply && scripts/novagram-local.sh hide" >&2
        exit 1
    fi
}

case "${1:-}" in
    hide) hide ;;
    show) show ;;
    check) check ;;
    *)
        echo "usage: scripts/novagram-local.sh hide|show|check" >&2
        exit 2
        ;;
esac
