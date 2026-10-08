#!/usr/bin/env bash
# herdr-team — bring up a team charter (ψ/teams/*.yaml) as panes in ONE herdr space:
# the worktree's space, Fibonacci layout (first member left and biggest, the rest stacked
# on the right), each worker started with its engine, named, and given its prompt.
set -uo pipefail

usage() {
  cat <<'U'
usage: herdr-team.sh <worktree> <charter.yaml> [--dry-run] [--no-brief]
  <worktree>      path of the worktree whose herdr space holds the team
  <charter.yaml>  team charter; workers are members with role != lead, in file order
U
  exit 64
}
die() { echo "REFUSING: $*" >&2; exit 1; }

[ $# -ge 2 ] || usage
case "$1" in -h|--help) usage ;; esac
# pwd -P: herdr reports real paths (/private/tmp/…, not /tmp/…); a symlinked path never matched
# its open space (2026-10-05, found while testing the example charter)
WT=$(cd "$1" 2>/dev/null && pwd -P) || die "no such worktree: $1"
CH=$2; shift 2
[ -f "$CH" ] || CH="$WT/$CH"; [ -f "$CH" ] || die "no charter: $CH"
DRY=0; BRIEF=1
while [ $# -gt 0 ]; do case "$1" in --dry-run) DRY=1 ;; --no-brief) BRIEF=0 ;; *) usage ;; esac; shift; done
command -v yq >/dev/null || die "yq is required"

# Engine commands: the charter's engines map wins; these are the fleet defaults.
default_cmd() {
  case "$1" in
    omp)    echo "omp --approval-mode=yolo" ;;
    omx)    echo "OMX_AUTO_UPDATE=0 omx --direct --madmax" ;;
    codex)  echo "codex --dangerously-bypass-approvals-and-sandbox" ;;
    claude) echo "claude" ;;
    *)      echo "" ;;
  esac
}

N=$(yq '[.members[] | select(.role != "lead")] | length' "$CH")
[ "$N" -ge 1 ] || die "charter has no workers"
names=(); engines=(); cmds=(); cwds=(); prompts=()
for i in $(seq 0 $((N - 1))); do
  m=".members | map(select(.role != \"lead\")) | .[$i]"
  n=$(yq "$m.name" "$CH"); e=$(yq "$m.engine" "$CH")
  c=$(yq ".engines.\"$e\" // \"\"" "$CH"); [ -n "$c" ] || c=$(default_cmd "$e")
  [ -n "$c" ] || die "no command for engine '$e' (member $n)"
  [[ "$n" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die "member name must be a valid herdr agent name: $n"
  d=$(yq "$m.cwd // \"\"" "$CH"); dir="$WT${d:+/$d}"
  [ -d "$dir" ] || die "member $n cwd does not exist: $dir"
  names+=("$n"); engines+=("$e"); cmds+=("$c"); cwds+=("$dir")
  prompts+=("$(yq "$m.prompt // \"\"" "$CH" | tr '\n' ' ' | sed 's/  */ /g; s/ $//')")
done

# The worktree's space and its root pane (a bare shell).
space=$(herdr worktree list --cwd "$WT" 2>/dev/null \
  | jq -r --arg p "$WT" '.result.worktrees[] | select(.path == $p) | .open_workspace_id // empty')
[ -n "$space" ] || die "no open herdr space for $WT (herdr worktree open --path $WT)"
root=$(herdr pane list | jq -r --arg s "$space" '[.result.panes[] | select(.workspace_id == $s)] | .[0].pane_id // empty')
count=$(herdr pane list | jq --arg s "$space" '[.result.panes[] | select(.workspace_id == $s)] | length')
[ -n "$root" ] || die "space $space has no pane"

echo "team   : $(yq .name "$CH")  ($N workers, fibonacci)  space $space"
for i in "${!names[@]}"; do
  pos=left; [ "$i" -gt 0 ] && pos="right-$i"
  printf '  %-12s %-5s %-8s %s\n' "${names[$i]}" "${engines[$i]}" "$pos" "${cmds[$i]}"
done
if [ "$DRY" = 1 ]; then echo "DRY RUN — nothing spawned"; exit 0; fi
[ "${HERDR_ENV:-}" = 1 ] || die "not inside a herdr pane"
[ "$count" = 1 ] || die "space $space already has $count panes; herdr-team only lays out a fresh space"
herdr agent list | jq -e --arg p "$root" '.result.agents[] | select(.pane_id == $p)' >/dev/null 2>&1 \
  && die "root pane $root already holds an agent"

# Fibonacci: pane 0 keeps the golden share on the left; each later split hands the rest
# down the stack (right, then down, then right ...). The last split halves what is left.
panes=("$root"); prev=$root
# `seq 1 0` counts DOWN on macOS (1, 0), so a one-member team must skip this loop explicitly.
for i in $( [ "$N" -gt 1 ] && seq 1 $((N - 1)) ); do
  if [ "$i" = 1 ]; then dir=right; else [ $((i % 2)) = 0 ] && dir=down || dir=right; fi
  ratio=0.618; [ "$i" = $((N - 1)) ] && [ "$i" -gt 1 ] && ratio=0.5
  new=$(herdr pane split "$prev" --direction "$dir" --ratio "$ratio" --cwd "${cwds[$i]}" --no-focus \
    | jq -r '.result.pane.pane_id // .result.pane_id // empty')
  [ -n "$new" ] || die "split $i failed"
  panes+=("$new"); prev=$new
done

# Start each member: cd, a throwaway command so direnv loads, then the engine.
for i in "${!names[@]}"; do
  p=${panes[$i]}
  herdr pane run "$p" "cd '${cwds[$i]}' && echo \"TOK=\${CLAUDE_TOKEN_NAME:-none}\"" >/dev/null
  herdr pane wait-output "$p" --match 'TOK=' --timeout 40000 >/dev/null 2>&1 || true
  herdr pane run "$p" "${cmds[$i]}" >/dev/null
  echo "start  : ${names[$i]} in $p"
done

# Wait for each to settle, name it, brief it. omp may not register as a herdr agent, so the
# brief is typed with pane run (one line), which works for any TUI prompt.
for i in "${!names[@]}"; do
  p=${panes[$i]}; ok=""
  for _ in $(seq 1 24); do
    sleep 5
    # Two trust gates seen: omx "Hooks need review" (2026-09-16) and codex "Trust this
    # folder?" on a never-seen repo (2026-09-29, <pane>). Both are the human's call.
    if herdr pane read "$p" --source visible --lines 20 2>/dev/null | grep -qE "Hooks need review|Trust this folder\?"; then
      echo "gate   : ${names[$i]} ($p) is at a trust gate (hooks or folder) — the human answers it; brief not sent" >&2
      ok=gate; break
    fi
    st=$(herdr pane get "$p" 2>/dev/null | jq -r '.result.pane | "\(.agent // "none") \(.agent_status // "-")"')
    case "$st" in *" idle") ok=$st; break ;; esac
    # no agent detection (omp): settle when the screen stops changing
    a=$(herdr pane read "$p" --source visible --lines 30 2>/dev/null | md5); sleep 3
    b=$(herdr pane read "$p" --source visible --lines 30 2>/dev/null | md5)
    [ "$a" = "$b" ] && case "$st" in none*) ok="settled"; break ;; esac
  done
  herdr agent rename "$p" "${names[$i]}" >/dev/null 2>&1 || true
  [ "$ok" = gate ] && continue
  [ -n "$ok" ] || { echo "warn   : ${names[$i]} ($p) never settled; brief not sent — herdr pane read $p" >&2; continue; }
  if [ "$BRIEF" = 1 ] && [ -n "${prompts[$i]}" ]; then
    herdr pane run "$p" "${prompts[$i]}" >/dev/null && echo "brief  : ${names[$i]} ($ok)"
  fi
done

echo "OK — space $space: ${panes[*]}"
