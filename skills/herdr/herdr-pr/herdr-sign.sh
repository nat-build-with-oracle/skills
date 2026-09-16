#!/usr/bin/env bash
# Emit the "Built by" signature block for a PR/issue comment.
# Describes a herdr SESSION (the pane), not whatever directory the shell is in,
# and addresses it by agent name.
#
#   herdr-sign.sh <model-id> [pane-id] [--work <path>] [--ref <committish>]
#                  [--full] [--tall]
#
# Output is compact by default — one line per field, ~28 lines. --tall emits the
# same YAML with every value as a folded block scalar on its own line (~47
# lines), which needs no quoting and survives any value verbatim.
#
# --ref reports a commit the working tree is not sitting on: a merged PR whose
# SHA the rebase rewrote, or a second PR in the same repo. Without it a signature
# can only describe whatever branch happens to be checked out, so signing PR B
# while working PR A meant checking B out first — on a repo with a server running
# from it.
#
# --work names the repo the PR actually lives in. An oracle working an INCUBATED
# repo has its pane cwd in the oracle vault and the diff in $(ghq root)/..., so
# session facts and code facts come from two different checkouts. Without --work
# the block reports the ORACLE's branch and HEAD on someone else's PR: it looks
# authoritative and points at an unrelated commit.
#
# Visibility decides how much local layout is printed. A public repo gets a
# redacted block — no absolute paths, no transcript, no memory dir, no socket, no
# private oracle slug — because those map a machine reviewers cannot reach anyway.
# Unknown visibility redacts too; --full overrides once you have checked.
set -uo pipefail

MODEL=""; pane=""; work=""; ref=""; force_full=0; compact=1; positional=()
while [ $# -gt 0 ]; do
    case "$1" in
        --work|-w) work="${2:-}"; shift 2 ;;
        --ref)     ref="${2:-}"; shift 2 ;;
        --full)    force_full=1; shift ;;
        --compact) compact=1; shift ;;   # default; kept so scripts that pass it still work
        --tall)    compact=0; shift ;;   # one value per line, as folded block scalars
        --help|-h) sed -n '2,16p' "$0"; exit 0 ;;
        *)         positional+=("$1"); shift ;;
    esac
done
MODEL="${positional[0]:-<your exact model id>}"
pane="${positional[1]:-${HERDR_PANE_ID:-}}"

facts=$(herdr agent get "$pane" 2>/dev/null | python3 -c '
import json, sys
try:
    a = json.load(sys.stdin)["result"]["agent"]
except Exception:
    sys.exit(1)
print("\x1f".join([
    a.get("name") or "",
    a.get("pane_id") or "",
    a.get("tab_id") or "",
    a.get("workspace_id") or "",
    a.get("agent") or "",
    a.get("terminal_title_stripped") or "",
    (a.get("agent_session") or {}).get("value", ""),
    a.get("cwd") or "",
]))' 2>/dev/null)

# \x1f, not tab: bash collapses runs of whitespace IFS chars, so an agent with no
# session id or no name silently shifts every later field one column left.
IFS=$'\x1f' read -r name pane_id tab wsid agent title sess pane_cwd <<<"$facts"

# No pane means no session to point at. Emitting a block of "unknown" would be the
# exact failure this block exists to prevent: authoritative-looking, reaching nobody.
if [ -z "${pane_id:-}" ]; then
    echo "herdr-sign: no herdr agent for pane '${pane:-<unset>}'." >&2
    echo "  Run this from inside a herdr pane (HERDR_PANE_ID set), or pass one:" >&2
    echo "    herdr-sign.sh <model-id> <pane-id>     # herdr agent list" >&2
    exit 1
fi

# The block describes the session, so every path is resolved from the PANE's cwd.
# Signing $PWD would describe whatever directory the shell wandered into.
root="${pane_cwd:-$PWD}"

# A named agent is addressable by name; an unnamed one only by pane id, which does
# not survive a herdr restart. Claim a name before signing.
addr="${name:-${pane_id:-<pane>}}"
label=$(herdr workspace get "${wsid:-x}" 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["workspace"].get("label",""))' 2>/dev/null)

repo_root=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || echo "$root")
common=$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)
case "$common" in
    /*) main=$(cd "$(dirname "$common")" && pwd) ;;
    *)  main=$(cd "$repo_root/$(dirname "${common:-.git}")" 2>/dev/null && pwd || echo "$repo_root") ;;
esac
[ "$main" = "$repo_root" ] && where="main checkout" || where="worktree of ${main}"

# Two passes: BSD sed has no lazy quantifier, so strip .git before matching org/repo.
slug=$(git -C "$root" remote get-url origin 2>/dev/null | sed -E 's|\.git$||; s|.*[:/]([^/]+/[^/]+)$|\1|')
oracle=$(basename "$main"); oracle=${oracle%-oracle}

# The work repo: where the diff is. Defaults to the session's own checkout, so an
# oracle signing its own PR behaves exactly as before.
work_root="$root"
[ -n "$work" ] && work_root=$(git -C "$work" rev-parse --show-toplevel 2>/dev/null || echo "$work")
work_slug=$(git -C "$work_root" remote get-url origin 2>/dev/null | sed -E 's|\.git$||; s|.*[:/]([^/]+/[^/]+)$|\1|')
work_branch=$(git -C "$work_root" branch --show-current 2>/dev/null)
work_head=$(git -C "$work_root" log --oneline -1 2>/dev/null)
if [ -n "$ref" ]; then
    # Fail loudly: a typo'd ref would otherwise silently fall back to the
    # checkout and sign the wrong commit under a confident-looking block.
    if ! work_head=$(git -C "$work_root" log --oneline -1 "$ref" 2>/dev/null); then
        echo "herdr-sign: --ref '$ref' does not resolve in $work_root" >&2
        exit 1
    fi
    work_branch="$ref"
fi

# The session tree's own branch and head. --ref names the commit the signature
# CITES, and when the PR's repo is the session's own checkout there is no
# incubated stanza to carry it — so it has to land here or the flag is a silent
# no-op in exactly the same-repo case traps 5 and 6 tell people to use it for.
tree_branch=$(git -C "$root" branch --show-current 2>/dev/null)
tree_head=$(git -C "$root" log --oneline -1 2>/dev/null)
if [ -n "$ref" ] && [ "$work_root" = "$root" ]; then
    tree_branch="$work_branch"
    tree_head="$work_head"
fi

# /incubate drops this breadcrumb into every repo it clones. It is the only record
# tying a foreign checkout back to the oracle working it.
incubated=""
if [ -f "$work_root/.claude/INCUBATED_BY" ]; then
    when=$(sed -n 's/^date: //p' "$work_root/.claude/INCUBATED_BY" | head -1)
    incubated="incubated by ${oracle}${when:+ on }${when}"
fi

# Where the work repo actually is. Naming the repo without its checkout tells a
# reader which code to look at but not how to reach it — and for an incubated
# repo the ghq clone and the vault symlink are two different ways in, so both
# are printed. The symlink is the oracle-side handle /incubate created.
work_wt=""
work_common=$(git -C "$work_root" rev-parse --git-common-dir 2>/dev/null)
case "$work_common" in
    /*) work_main=$(cd "$(dirname "$work_common")" && pwd) ;;
    *)  work_main=$(cd "$work_root/$(dirname "${work_common:-.git}")" 2>/dev/null && pwd || echo "$work_root") ;;
esac
[ "$work_main" != "$work_root" ] && work_wt="worktree of ${work_main}"

incubate_link=""
if [ -n "$work_slug" ] && [ -L "$root/ψ/incubate/$work_slug/origin" ]; then
    incubate_link="$root/ψ/incubate/$work_slug/origin"
fi

# Redact by default, open up only on proof of privacy. Guessing "private" wrong
# publishes a machine layout to the internet, and GitHub has already mailed it out
# by the time anyone notices.
visibility="unknown"
if [ -n "$work_slug" ]; then
    case "$(gh repo view "$work_slug" --json isPrivate --jq .isPrivate 2>/dev/null)" in
        true)  visibility="private" ;;
        false) visibility="public"  ;;
    esac
fi
redact=1
[ "$visibility" = "private" ] && redact=0
[ "$force_full" = "1" ] && redact=0

# Each agent stores transcripts under its own scheme, and the cwd encodings differ
# in ways that look like typos but aren't. Claude replaces "/" AND "." with "-";
# omp replaces only "/" and wraps the whole thing in "--". Guessing wrong prints a
# path that does not exist, which is the one thing this block must never do.
claude_key() { local p=${1//\//-}; echo "${p//./-}"; }             # /a/b.c -> -a-b-c
omp_key()    { local p=${1#/}; echo "--${p//\//-}--"; }            # /a/b.c -> --a-b.c--
memory="~/.claude/projects/$(claude_key "$main")/memory"

case "$agent" in
    claude)
        transcript="${CODEX_COMPANION_TRANSCRIPT_PATH:-$HOME/.claude/projects/$(claude_key "$root")/${sess}.jsonl}"
        ;;
    omp)
        # herdr reports no session id for omp, so take the newest transcript in the
        # cwd's session dir and read the id back off its filename.
        dir="$HOME/.omp/agent/sessions/$(omp_key "$root")"
        transcript=$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)
        [ -n "$transcript" ] && sess=$(basename "$transcript" .jsonl)
        memory="— (omp: session dir is $dir)"
        ;;
    codex)
        # Date-partitioned rollouts; herdr gives the uuid, the date is in the name.
        transcript=$(find "$HOME/.codex/sessions" -name "rollout-*${sess}*.jsonl" 2>/dev/null | head -1)
        memory="— (codex: rollouts only)"
        ;;
esac
transcript="${transcript:-unknown}"
sess="${sess:-unknown}"

# Valid YAML, so the block is machine-readable with `yq` and not just aligned
# text. Every value is a folded block scalar (`>-`) on its own line: inside one,
# "#" starts no comment and ":" separates no key, so a git subject like
# "feat: share… #31" survives verbatim. Quoted one-liners needed escaping rules
# per value and truncated silently at the first " #" when one was missed.

# The vault symlink: the oracle-side handle on this checkout. Prints in both
# blocks — the public block already carries cwd and the worktree parent, which
# hold the same private slug, so withholding this one path bought nothing.
link_line=""
[ -n "$incubate_link" ] && link_line="
  link: >-
    ${incubate_link}"

# One composed block, not two heredocs. Two drifted every time a field changed:
# a line added to the full block silently never reached the public one.
# Groups answer the four questions a reviewer actually asks in order — who built
# it, from which tree, against which repo, and how do I reach them.

sess_private=""
herdr_private=""
if [ "$redact" = "0" ]; then
    sess_private="
  transcript: >-
    ${transcript/#$HOME/\~}
  memory: >-
    ${memory}"
    herdr_private="
  socket: >-
    ${HERDR_SOCKET_PATH:-~/.config/herdr/herdr.sock (default; not run from a pane)}"
fi

# The incubated group only exists when the PR's repo is not the session's own.
incubated_group=""
if [ "$work_root" != "$root" ]; then
    incubated_group="
incubated:
  repo: >-
    ${work_slug:-$work_root}
  branch: >-
    ${work_branch:--}
  head: >-
    ${work_head:--}
  work: >-
    ${work_root}${work_wt:+
  wt: >-
    ${work_wt}}${link_line}${incubated:+
  by: >-
    ${incubated#incubated by }}
"
fi

block=$(cat <<SIG
## Built by

\`\`\`yaml
agent:
  who: >-
    ${oracle} — ${slug}
  model: >-
    ${MODEL}
  runtime: >-
    ${agent:--}

worktree:
  cwd: >-
    ${root}
  branch: >-
    ${tree_branch}
  wt: >-
    ${where}
  head: >-
    ${tree_head}
${incubated_group}
session:
  id: >-
    ${sess}${sess_private}

herdr:
  address: >-
    ${addr}
  pane: >-
    ${pane_id:--}
  tab: >-
    ${tab:--}
  space: >-
    ${label:-${wsid:--}}
  title: >-
    ${title:--}${herdr_private}
\`\`\`
${redact:+}
$([ "$redact" = "1" ] && printf '%s' "Agent-private storage — transcript, memory dir, herdr socket — is omitted: this
repo is ${visibility}.")

**Reach this session** — from any pane, agent, or machine with the herdr CLI:

\`\`\`bash
herdr agent prompt ${addr} "question about this PR"
herdr agent read   ${addr}
herdr agent focus  ${addr}
herdr agent attach ${addr}
\`\`\`
SIG
)

# Compact (the default) folds "key: >-" + its indented value back onto one line.
# The value must be re-quoted on the way: inline YAML reads " #" as a comment and
# ": " as a key separator, which is exactly what the block-scalar form avoids, so
# this transform is the only place those rules come back. --tall skips it.
if [ "$compact" = "1" ]; then
    block=$(printf '%s\n' "$block" | awk '
        match($0, /^[ ]+[A-Za-z_]+: >-$/) {
            key = $0; sub(/: >-$/, ":", key)
            indent = key; sub(/[^ ].*$/, "", indent)
            name = key; sub(/^[ ]+/, "", name)
            if ((getline value) > 0) {
                sub(/^[ ]+/, "", value)
                gsub(/\x27/, "\x27\x27", value)
                printf "%s%-11s \x27%s\x27\n", indent, name, value
                next
            }
            print key
            next
        }
        { print }
    ')
fi
printf '%s\n' "$block"


if [ "$redact" = "1" ]; then
    echo "herdr-sign: ${work_slug:-this repo} is ${visibility} — printed the redacted block (no local paths)." >&2
    [ "$visibility" = "unknown" ] && echo "  gh could not read visibility. Use --full only after confirming the repo is private." >&2
else
    [ -f "${transcript/#\~/$HOME}" ] || echo "warning: transcript path does not exist: $transcript" >&2
fi
if [ -n "$work" ] && [ -z "$work_slug" ]; then
    echo "warning: --work ${work} has no origin remote; the repo line falls back to a local path." >&2
fi
if [ -z "${name:-}" ]; then
    echo "warning: this agent has no name, so the block addresses a pane id that dies with the herdr server." >&2
    echo "  herdr agent rename ${pane_id:-\$HERDR_PANE_ID} ${label:-<name>}" >&2
fi
