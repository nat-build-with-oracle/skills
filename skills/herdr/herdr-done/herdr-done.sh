#!/usr/bin/env bash
# Audit whether a herdr session is safe to close.
#
#   herdr-done.sh [pane-id] [--work <path>] [--quiet]
#
# READ-ONLY. It never commits, pushes, merges, or kills a pane — it reports what
# would be lost if the pane went away right now, and exits non-zero when anything
# would be. Closing a pane is the irreversible half; that stays with whoever ran
# the skill, who can see the report first.
#
# Like herdr-sign.sh it describes the SESSION (the pane's cwd), not whatever
# directory the shell wandered into, and addresses it by agent name.
#
# Exit: 0 = nothing would be lost. 1 = blockers. 2 = no herdr agent for the pane.
set -uo pipefail

pane=""; work=""; quiet=0; positional=()
while [ $# -gt 0 ]; do
    case "$1" in
        --work|-w) work="${2:-}"; shift 2 ;;
        --quiet|-q) quiet=1; shift ;;
        --help|-h) sed -n '2,14p' "$0"; exit 0 ;;
        *) positional+=("$1"); shift ;;
    esac
done
pane="${positional[0]:-${HERDR_PANE_ID:-}}"

facts=$(herdr agent get "$pane" 2>/dev/null | python3 -c '
import json, sys
try:
    a = json.load(sys.stdin)["result"]["agent"]
except Exception:
    sys.exit(1)
print("\x1f".join([
    a.get("name") or "",
    a.get("pane_id") or "",
    a.get("workspace_id") or "",
    a.get("agent") or "",
    a.get("agent_status") or "",
    a.get("cwd") or "",
]))' 2>/dev/null)

# \x1f, not tab — bash collapses runs of whitespace IFS chars, so an agent with no
# name silently shifts every later field one column left (herdr-pr trap 3).
IFS=$'\x1f' read -r name pane_id wsid agent status pane_cwd <<<"$facts"

if [ -z "${pane_id:-}" ]; then
    echo "herdr-done: no herdr agent for pane '${pane:-<unset>}'." >&2
    echo "  Run from inside a herdr pane (HERDR_PANE_ID set), or pass one:" >&2
    echo "    herdr-done.sh <pane-id>      # herdr agent list" >&2
    exit 2
fi

root="${pane_cwd:-$PWD}"
[ -n "$work" ] && root=$(git -C "$work" rev-parse --show-toplevel 2>/dev/null || echo "$work")
addr="${name:-$pane_id}"

if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    echo "herdr-done: $root is not a git repo — nothing to audit." >&2
    exit 0
fi

repo_root=$(git -C "$root" rev-parse --show-toplevel)
branch=$(git -C "$root" branch --show-current)
head=$(git -C "$root" log --oneline -1 2>/dev/null)
slug=$(git -C "$root" remote get-url origin 2>/dev/null | sed -E 's|\.git$||; s|.*[:/]([^/]+/[^/]+)$|\1|')

common=$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)
case "$common" in
    /*) main=$(cd "$(dirname "$common")" && pwd) ;;
    *)  main=$(cd "$repo_root/$(dirname "${common:-.git}")" 2>/dev/null && pwd || echo "$repo_root") ;;
esac
[ "$main" = "$repo_root" ] && is_wt=0 || is_wt=1

blockers=(); warnings=(); notes=()

# 1. Uncommitted work. Counted separately: tracked edits are the loss that matters,
#    untracked files are often build junk, so they warn rather than block.
dirty=$(git -C "$root" status --porcelain --untracked-files=no | wc -l | tr -d ' ')
untracked=$(git -C "$root" ls-files --others --exclude-standard | wc -l | tr -d ' ')
[ "$dirty" -gt 0 ] && blockers+=("$dirty uncommitted change(s) to tracked files")
[ "$untracked" -gt 0 ] && warnings+=("$untracked untracked file(s) — build junk, or work never added?")

# 2. Commits that exist only here. No upstream at all is the worse case: the branch
#    lives on one disk and nothing off this machine has ever seen it.
upstream=$(git -C "$root" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
if [ -z "$upstream" ]; then
    if [ -n "$branch" ]; then
        local_only=$(git -C "$root" log --oneline "$branch" --not --remotes 2>/dev/null | wc -l | tr -d ' ')
        if [ "$local_only" -gt 0 ]; then
            blockers+=("branch '$branch' has no upstream and $local_only commit(s) no remote has")
        else
            notes+=("branch '$branch' has no upstream, but every commit is reachable from a remote")
        fi
    fi
else
    ahead=$(git -C "$root" rev-list --count "$upstream".."$branch" 2>/dev/null || echo 0)
    behind=$(git -C "$root" rev-list --count "$branch".."$upstream" 2>/dev/null || echo 0)
    [ "$ahead" -gt 0 ] && blockers+=("$ahead commit(s) not pushed to $upstream")
    [ "$behind" -gt 0 ] && notes+=("$behind commit(s) behind $upstream — pull before resuming")
fi

# 3. Detached HEAD. Commits made here are reachable from nothing once the pane
#    closes and the reflog is the only record.
[ -z "$branch" ] && blockers+=("detached HEAD — commits here belong to no branch")

# 4. Name drift. herdr-wt's convention is dir == branch == space; when they differ,
#    a later session reads the directory name and trusts it (this is how a README
#    branch ended up living in a worktree named for something else).
dir_name=$(basename "$repo_root")
if [ "$is_wt" = "1" ] && [ -n "$branch" ] && [ "$dir_name" != "$branch" ]; then
    warnings+=("worktree dir '$dir_name' != branch '$branch' — dir name will mislead the next session")
fi
label=$(herdr workspace get "${wsid:-x}" 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["workspace"].get("label",""))' 2>/dev/null)
if [ -n "$label" ] && [ "$is_wt" = "1" ] && [ "$label" != "$dir_name" ]; then
    notes+=("herdr space '$label' != worktree dir '$dir_name'")
fi

# 5. The PR, if there is one. An open PR is not a blocker — leaving one open is a
#    normal way to end a day — but closing the pane that can answer review comments
#    without saying so is how a PR goes quiet.
pr_state=""; pr_num=""
if [ -n "$branch" ] && command -v gh >/dev/null 2>&1; then
    read -r pr_num pr_state <<<"$(gh pr list --repo "$slug" --head "$branch" --state all \
        --json number,state --jq '.[0] | "\(.number) \(.state)"' 2>/dev/null)"
    case "$pr_state" in
        OPEN)   notes+=("PR #$pr_num is OPEN — reviewers may still need this session") ;;
        MERGED) notes+=("PR #$pr_num merged — branch is safe to leave behind") ;;
        CLOSED) notes+=("PR #$pr_num closed unmerged") ;;
        *)      [ -n "$branch" ] && notes+=("no PR for '$branch'") ;;
    esac
fi

# 6. A locked worktree outlives the pane on purpose; an unlocked one can be pruned
#    out from under work that is still going.
if [ "$is_wt" = "1" ]; then
    if git -C "$main" worktree list --porcelain 2>/dev/null |
       awk -v p="$repo_root" '$1=="worktree"{w=($2==p)} w&&$1=="locked"{found=1} END{exit !found}'; then
        notes+=("worktree is locked — survives a prune")
    else
        warnings+=("worktree is NOT locked — 'git worktree prune' can remove it")
    fi
fi

verdict="clean"
[ ${#warnings[@]} -gt 0 ] && verdict="warnings"
[ ${#blockers[@]} -gt 0 ] && verdict="blocked"

if [ "$quiet" = "0" ]; then
    printf '## Session wrap-up — %s\n\n' "$addr"
    printf '```yaml\n'
    printf 'session:\n'
    printf "  agent:    '%s'\n" "$addr"
    printf "  runtime:  '%s'\n" "$agent"
    printf "  status:   '%s'\n" "$status"
    printf "  pane:     '%s'\n" "$pane_id"
    printf 'tree:\n'
    printf "  cwd:      '%s'\n" "$repo_root"
    printf "  branch:   '%s'\n" "${branch:-<detached>}"
    printf "  head:     '%s'\n" "${head//\'/\'\'}"
    [ "$is_wt" = "1" ] && printf "  wt:       'worktree of %s'\n" "$main"
    printf 'verdict:    %s\n' "$verdict"
    printf '```\n\n'
    for b in "${blockers[@]:-}"; do [ -n "$b" ] && printf -- '- BLOCKER: %s\n' "$b"; done
    for w in "${warnings[@]:-}"; do [ -n "$w" ] && printf -- '- warning: %s\n' "$w"; done
    for n in "${notes[@]:-}"; do [ -n "$n" ] && printf -- '- note:    %s\n' "$n"; done
    echo
fi

[ "$verdict" = "blocked" ] && exit 1
exit 0
