#!/usr/bin/env bash
# What every herdr agent is doing right now, and what it last printed.
#
#   herdr-peek.sh [name-or-pane] [--lines N] [--all] [--quiet]
#
# No argument lists every agent, one line each. A name or pane id tails that
# agent's terminal instead. --all tails every agent.
#
# READ-ONLY, and deliberately not `herdr agent focus`: peeking must never move
# the human's window or steal the pane they are typing in.
set -uo pipefail

target=""; lines=20; all=0
while [ $# -gt 0 ]; do
    case "$1" in
        --lines|-n) lines="${2:-20}"; shift 2 ;;
        --all|-a)   all=1; shift ;;
        --help|-h)  sed -n '2,11p' "$0"; exit 0 ;;
        *)          target="$1"; shift ;;
    esac
done

list=$(herdr agent list 2>/dev/null)
if [ -z "$list" ]; then
    echo "herdr-peek: herdr is not answering — is the server running?" >&2
    exit 2
fi

# \x1f, not tab: an agent with no name would otherwise shift every later field
# one column left, and a nameless agent is exactly the common case here
# (herdr-pr trap 3 — the same parse, the same reason).
rows=$(printf '%s' "$list" | python3 -c '
import json, sys
try:
    agents = json.load(sys.stdin)["result"]["agents"]
except Exception:
    sys.exit(1)
for a in agents:
    print("\x1f".join([
        a.get("name") or a.get("pane_id") or "?",
        a.get("agent_status") or "?",
        a.get("agent") or "?",
        a.get("pane_id") or "?",
        a.get("cwd") or "",
        a.get("terminal_title_stripped") or "",
        "*" if a.get("focused") else " ",
    ]))' 2>/dev/null)

if [ -z "$rows" ]; then
    echo "herdr-peek: no agents." >&2
    exit 0
fi

# A status glyph, never colour alone — this gets read over SSH and in pipes.
glyph() {
    case "$1" in
        working)  printf '◐' ;;
        idle)     printf '○' ;;
        waiting)  printf '◔' ;;
        *)        printf '·' ;;
    esac
}

tail_one() {
    printf '\n─── %s ─── %s\n' "$1" "${2:-}"
    herdr agent read "$1" --lines "$lines" --format text 2>/dev/null \
        || echo "  (no output — agent may have never printed, or the name is stale)"
}

if [ -n "$target" ]; then
    tail_one "$target"
    exit 0
fi

printf '%s\n' "$rows" | while IFS=$'\x1f' read -r name status runtime pane cwd title focus; do
    printf '%s %s %-22s %-8s %-9s %s\n' "$focus" "$(glyph "$status")" "$name" "$status" "$runtime" "$title"
    printf '     %s\n' "$cwd"
done

if [ "$all" = "1" ]; then
    printf '%s\n' "$rows" | while IFS=$'\x1f' read -r name status runtime pane cwd title focus; do
        tail_one "$name" "$status"
    done
fi
