#!/bin/bash
# novagram-upstream-update.sh - merge the latest official Telegram macOS (upstream/master) on a new branch.
#
# Steps:
#   1. check the tree: on main, nothing staged, the TelegramCore hooks in submodules/telegram-ios match fork-patches/
#   2. undo the local Xcode 27 changes (scripts/xcode27.sh revert + the MTProtoEngine target) so they stay out of every commit
#   3. fetch upstream, create feature/upstream-<date>, merge upstream/master
#   4. update the submodules upstream moved, re-apply the TelegramCore fork patches
#   5. put the Xcode 27 changes back, check that no "// Novagram" hook was lost in the merge
#   6. build (Debug, low priority) and print what to check on screen
#
# main is never touched. When the build is green and the app was checked on screen:
#   git switch main && git merge --ff-only <branch> && git push origin main && git branch -d <branch>
#
# Usage:
#   scripts/novagram-upstream-update.sh             everything (steps 1-6)
#   scripts/novagram-upstream-update.sh --check     only report what upstream has: no branch, no merge
#   scripts/novagram-upstream-update.sh --finish    after resolving merge conflicts by hand: steps 4-6
#   NOVAGRAM_TRAILER='Co-Authored-By: ...'          optional trailer line for the merge commit
#
# Exit codes: 0 ok, 1 tree not ready, 2 merge conflicts (resolve, commit, then --finish),
#             3 submodule or fork patch problem, 4 a hook was lost, 5 build failed

set -o pipefail
cd "$(dirname "$0")/.." || exit 1
STATE=".git/novagram-upstream"
LOG="${NOVAGRAM_UPSTREAM_LOG:-/tmp/novagram-upstream-update.log}"
SUBMODULE="submodules/telegram-ios"
PATCH="$(pwd)/fork-patches/telegramcore-hooks.patch" # absolute: git -C <submodule> reads it from there
# bumped by hand for Xcode 27, not covered by scripts/xcode27.sh
EXTRA_BUMP=(core-xprojects/mtproto-engine/MTProtoEngine.xcodeproj/project.pbxproj)
MODE="${1:-start}"
RESTORE_ON_EXIT=0

: > "$LOG"

die() {
    local code="${2:-1}"
    echo "ERROR: $1" >&2
    if [ "$RESTORE_ON_EXIT" = 1 ]; then
        restore_local
    fi
    exit "$code"
}

# ---- local-only changes (never committed) -------------------------------------

revert_local() {
    scripts/novagram-local.sh show >> "$LOG" 2>&1 || die "scripts/novagram-local.sh show failed, see $LOG"
    scripts/xcode27.sh revert >> "$LOG" 2>&1 || die "scripts/xcode27.sh revert failed, see $LOG"
    local f
    for f in "${EXTRA_BUMP[@]}"; do
        git diff --quiet -- "$f" && continue
        if git diff -- "$f" | grep -E '^[-+]' | grep -vE '^(\+\+\+|---)' | grep -qv MACOSX_DEPLOYMENT_TARGET; then
            die "$f has changes besides the deployment target, commit or restore it first"
        fi
        git checkout -- "$f"
    done
}

restore_local() {
    RESTORE_ON_EXIT=0
    scripts/xcode27.sh apply >> "$LOG" 2>&1 || echo "WARNING: scripts/xcode27.sh apply failed, see $LOG" >&2
    local f
    for f in "${EXTRA_BUMP[@]}"; do
        [ -f "$f" ] && perl -pi -e 's/(MACOSX_DEPLOYMENT_TARGET = )(?:10|11)(?:\.\d+)*;/${1}12.0;/g' "$f"
    done
    scripts/novagram-local.sh hide >> "$LOG" 2>&1 || echo "WARNING: scripts/novagram-local.sh hide failed, see $LOG" >&2
}

# ---- TelegramCore fork patches ------------------------------------------------

check_fork_patches() {
    git -C "$SUBMODULE" apply --reverse --check "$PATCH" 2>> "$LOG" \
        || die "the hooks in $SUBMODULE do not match $PATCH; regenerate it first (see fork-patches/apply-telegramcore-patches.sh)" 3
    local f
    for f in fork-patches/telegramcore/*.swift; do
        cmp -s "$f" "$SUBMODULE/submodules/TelegramCore/Sources/$(basename "$f")" \
            || die "$(basename "$f") in $SUBMODULE differs from fork-patches/, copy it back first" 3
    done
    local extra
    extra="$(comm -23 <(git -C "$SUBMODULE" diff --name-only | sort) <(grep '^+++ b/' "$PATCH" | sed 's#^+++ b/##' | sort))"
    [ -z "$extra" ] || die "$SUBMODULE has changes that are not in $PATCH:
$extra" 3
}

apply_fork_patches() {
    ./fork-patches/apply-telegramcore-patches.sh >> "$LOG" 2>&1 \
        || die "the TelegramCore fork patches no longer apply (see $LOG and NOVAGRAM_HOOKS.md, 'Bot token login')" 3
}

update_moved_submodules() {
    local moved
    moved="$(git submodule status | awk '/^\+/ { print $2 }')"
    [ -z "$moved" ] && return
    echo "upstream moved submodules: $(echo "$moved" | tr '\n' ' ')"
    if echo "$moved" | grep -qx "$SUBMODULE"; then
        # take our hooks out so the checkout of the new commit is clean; apply_fork_patches puts them back
        git -C "$SUBMODULE" apply --reverse "$PATCH" >> "$LOG" 2>&1 || true
    fi
    local p
    for p in $moved; do
        git submodule update --init --recursive -- "$p" >> "$LOG" 2>&1 || die "git submodule update failed for $p, see $LOG" 3
    done
}

# ---- "// Novagram" hooks --------------------------------------------------------

hooks_snapshot() {
    git grep -c -e '// Novagram' -- ':!*.md' ':!docs/*' ':!*.xcframework/*' > "$1" || true
}

hooks_compare() {
    awk -F: '
        NR == FNR { before[$1] = $2; next }
        { after[$1] = $2 }
        END {
            lost = 0
            for (f in before) {
                if (!(f in after)) { printf "  LOST file with hooks: %s (%d)\n", f, before[f]; lost++ }
                else if (after[f] < before[f]) { printf "  FEWER hooks: %s (%d -> %d)\n", f, before[f], after[f]; lost++ }
            }
            for (f in after) if (!(f in before)) printf "  new file with hooks: %s (%d)\n", f, after[f]
            exit lost ? 1 : 0
        }' "$1" "$2"
}

# ---- reporting ---------------------------------------------------------------

upstream_report() { # $1 = our base commit, $2 = upstream commit
    local mb n
    mb="$(git merge-base "$1" "$2")" # only what upstream changed since we last merged
    n="$(git rev-list --count "$1..$2")"
    echo "upstream has $n new commits since $(git log -1 --format=%ad --date=short "$mb"):"
    git log --format='  %h %s' "$1..$2" | head -40
    [ "$n" -gt 40 ] && echo "  ... and $((n - 40)) more"
    echo "upstream changed $(git diff --name-only "$mb" "$2" | wc -l | tr -d ' ') files; these also hold our hooks (check them on screen):"
    comm -12 <(git diff --name-only "$mb" "$2" | sort) <(cut -d: -f1 "$STATE/hooks-before.txt" | sort) | sed 's/^/  /'
    echo "submodules moved by upstream: $(git diff --submodule=short "$mb" "$2" -- submodules third-party 2> /dev/null | grep -c '^diff --git')"
}

build() {
    echo "building (low priority)..."
    nice -n 19 ./novagram-build.sh || die "build failed; fix it on this branch, then run: $0 --finish" 5
}

finish() {
    [ -f "$STATE/branch" ] || die "no update in progress (run without --finish first)"
    local branch base up
    branch="$(cat "$STATE/branch")"
    base="$(cat "$STATE/base")"
    up="$(cat "$STATE/upstream")"
    [ "$(git rev-parse --abbrev-ref HEAD)" = "$branch" ] || die "switch to $branch first"
    [ -e .git/MERGE_HEAD ] && die "the merge is not committed yet: resolve the conflicts, git add, git commit, then run --finish"
    update_moved_submodules
    apply_fork_patches
    restore_local
    hooks_snapshot "$STATE/hooks-after.txt"
    echo "hook check (// Novagram lines per file, before -> after the merge):"
    if ! hooks_compare "$STATE/hooks-before.txt" "$STATE/hooks-after.txt"; then
        die "a hook was lost in the merge: restore it on this branch (NOVAGRAM_HOOKS.md), commit, then run: $0 --finish" 4
    fi
    echo "  no hook lost ($(awk -F: '{ s += $2 } END { print s + 0 }' "$STATE/hooks-after.txt") lines in $(wc -l < "$STATE/hooks-after.txt" | tr -d ' ') files)"
    build
    echo
    echo "DONE on branch $branch"
    upstream_report "$base" "$up"
    echo
    echo "next: check the app on screen (the files above first). Then:"
    echo "  git switch main && git merge --ff-only $branch && git push origin main && git branch -d $branch"
}

start() {
    [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "switch to main first (an update always starts from main)"
    [ -e .git/MERGE_HEAD ] && die "a merge is in progress: finish it (or run --finish)"
    git diff --cached --quiet || die "staged changes found, commit or unstage them first"
    RESTORE_ON_EXIT=1
    revert_local
    local dirty
    dirty="$(git status --porcelain --untracked-files=no --ignore-submodules=all -- . ':(exclude).claude/settings.local.json')"
    [ -z "$dirty" ] || die "uncommitted changes, commit or stash them first:
$dirty"
    check_fork_patches
    echo "fetching upstream..."
    git fetch --no-recurse-submodules upstream >> "$LOG" 2>&1 || die "git fetch upstream failed, see $LOG"
    local base up
    base="$(git rev-parse HEAD)"
    up="$(git rev-parse upstream/master)"
    mkdir -p "$STATE"
    hooks_snapshot "$STATE/hooks-before.txt"
    if git merge-base --is-ancestor "$up" "$base"; then
        echo "already up to date with upstream/master ($(git rev-parse --short "$up"))"
        restore_local
        exit 0
    fi
    upstream_report "$base" "$up"
    if [ "$MODE" = "--check" ]; then
        if git merge-tree --write-tree "$base" "$up" > /dev/null 2>&1; then
            echo "trial merge: no conflicts"
        else
            echo "trial merge: CONFLICTS in:"
            git merge-tree --write-tree --name-only "$base" "$up" 2> /dev/null | sed -n '2,/^$/p' | sed '/^$/d; s/^/  /'
        fi
        restore_local
        exit 0
    fi
    local branch n
    branch="feature/upstream-$(date +%Y-%m-%d)"
    n=2
    while git show-ref --verify --quiet "refs/heads/$branch"; do
        branch="feature/upstream-$(date +%Y-%m-%d)-$n"
        n=$((n + 1))
    done
    git switch -c "$branch" >> "$LOG" 2>&1 || die "could not create $branch, see $LOG"
    printf '%s\n' "$branch" > "$STATE/branch"
    printf '%s\n' "$base" > "$STATE/base"
    printf '%s\n' "$up" > "$STATE/upstream"
    local subject
    subject="merged upstream telegram-macos through $(git rev-parse --short "$up") ($(git rev-list --count "$base..$up") commits)"
    echo "merging upstream/master into $branch..."
    local merge_status=0
    if [ -n "${NOVAGRAM_TRAILER:-}" ]; then
        git -c submodule.recurse=false merge --no-ff --no-edit -m "$subject" -m "$NOVAGRAM_TRAILER" upstream/master >> "$LOG" 2>&1 || merge_status=$?
    else
        git -c submodule.recurse=false merge --no-ff --no-edit -m "$subject" upstream/master >> "$LOG" 2>&1 || merge_status=$?
    fi
    if [ "$merge_status" -ne 0 ] && [ ! -e .git/MERGE_HEAD ]; then
        die "git merge failed before merging anything (exit $merge_status), see $LOG"
    fi
    if ! git merge-base --is-ancestor upstream/master HEAD && [ ! -e .git/MERGE_HEAD ]; then
        die "upstream/master is not in HEAD after the merge, see $LOG"
    fi
    if [ -e .git/MERGE_HEAD ]; then
        RESTORE_ON_EXIT=0
        echo "merge CONFLICTS (our side of each file has this many // Novagram lines, listed in NOVAGRAM_HOOKS.md):"
        local f
        for f in $(git diff --name-only --diff-filter=U); do
            echo "  $f ($(git show ":2:$f" 2> /dev/null | grep -c '// Novagram'))"
        done
        echo "resolve them (keep every // Novagram line), git add, git commit, then run: $0 --finish"
        echo "(the Xcode 27 local changes stay reverted until --finish)"
        exit 2
    fi
    echo "merged: $(git log -1 --format='%h %s')"
    finish
}

case "$MODE" in
    start | --check) start ;;
    --finish) finish ;;
    *)
        echo "usage: $0 [--check|--finish]" >&2
        exit 2
        ;;
esac
