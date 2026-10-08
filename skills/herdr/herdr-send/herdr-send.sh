#!/usr/bin/env bash
# herdr-send — hand a task to ANOTHER oracle: open an issue in its repo, cut a worktree
# under its wt/ (the /herdr-wt flow), start claude | codex | omx there, brief it from the
# issue. Run with --dry-run first; it resolves everything and changes nothing.
set -uo pipefail

usage() {
  cat <<'U'
usage: herdr-send.sh <oracle> <slug> (--task "text" | --task-file FILE)
                     [--engine claude|codex|omx] [--incubate org/repo | --incubate-here]
                     [--base REF] [--dry-run]

  <oracle>        who gets the work, as maw knows it (neo, fireman, homekeeper ...)
  <slug>          short kebab-case name of the work; becomes the branch prefix
  --engine        agent to start in the worktree (default: claude)
  --incubate      the agent's first step is to clone org/repo and work on it
  --incubate-here same, with the repo of the current directory
U
  exit 64
}

die()  { echo "REFUSING: $*" >&2; exit 1; }
ask()  { echo "CONFLICT: $*" >&2; exit 2; }   # exit 2 = a human decides, then re-run

[ $# -ge 2 ] || usage
case "$1" in -h|--help) usage ;; esac
ORACLE=$1; SLUG=$2; shift 2
ENGINE=claude; TASK=""; INCUBATE=""; BASE=HEAD; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --engine)        ENGINE=${2:-}; shift 2 ;;
    --task)          TASK=${2:-}; shift 2 ;;
    --task-file)     TASK=$(cat "${2:-/dev/null}") || die "cannot read ${2:-}"; shift 2 ;;
    --incubate)      INCUBATE=${2:-}; shift 2 ;;
    # Take org/repo from the origin URL, not `gh repo view`: gh follows renames
    # (<org>/pulse -> pulse-oracle) and ghq would then clone a second copy.
    --incubate-here) INCUBATE=$(git remote get-url origin 2>/dev/null \
                       | sed -E 's#^(git@|https://)github\.com[:/]##; s#\.git$##')
                     [ -n "$INCUBATE" ] || die "--incubate-here: the current directory has no GitHub origin"; shift ;;
    --base)          BASE=${2:-}; shift 2 ;;
    --dry-run)       DRY=1; shift ;;
    -h|--help)       usage ;;
    *)               echo "unknown argument: $1" >&2; usage ;;
  esac
done

# ── validate input ───────────────────────────────────────────────────────────
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "slug must be kebab-case: $SLUG"
[ -n "$TASK" ] || die "no task: pass --task or --task-file"
case "$ENGINE" in
  claude) CMD="claude" ;;
  codex)  CMD="codex --dangerously-bypass-approvals-and-sandbox" ;;
  omx)    CMD="OMX_AUTO_UPDATE=0 omx --direct --madmax" ;;   # see /herdr-buddy for both flags
  *)      die "engine must be claude, codex or omx: $ENGINE" ;;
esac
if [ -n "$INCUBATE" ]; then
  [[ "$INCUBATE" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "--incubate wants org/repo: $INCUBATE"
  gh repo view "$INCUBATE" --json name -q .name >/dev/null 2>&1 || die "no access to $INCUBATE on GitHub"
fi
[ "$DRY" = 1 ] || [ "${HERDR_ENV:-}" = 1 ] || die "not inside a herdr pane"

# ── resolve the target oracle ────────────────────────────────────────────────
info=$(maw locate "$ORACLE" --json 2>/tmp/herdr-send.locate.$$) || true   # exits 1 on ambiguous
if [ -z "$info" ] || ! echo "$info" | jq -e . >/dev/null 2>&1; then
  # Seen 2026-09-29: an ambiguous name prints plain text on stderr, not JSON candidates.
  if grep -q 'matches' /tmp/herdr-send.locate.$$ 2>/dev/null; then
    echo "AMBIGUOUS: re-run with the org/repo form:" >&2; cat /tmp/herdr-send.locate.$$ >&2
    rm -f /tmp/herdr-send.locate.$$; exit 2
  fi
  cat /tmp/herdr-send.locate.$$ >&2 2>/dev/null; rm -f /tmp/herdr-send.locate.$$
  die "maw locate $ORACLE returned nothing"
fi
rm -f /tmp/herdr-send.locate.$$
if echo "$info" | jq -e 'has("candidates")' >/dev/null 2>&1; then
  echo "AMBIGUOUS: $ORACLE matches several oracles, re-run with one of:" >&2
  echo "$info" | jq -r '.candidates[] | "  \(.name)  (\(.kind // "-"))  \(.action // "")"' >&2
  exit 2
fi
# maw has returned the path as repoPath and as local_path; accept either.
TARGET=$(echo "$info" | jq -r '.repoPath // .local_path // empty')
[ -n "$TARGET" ] && git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1 \
  || die "$ORACLE resolved to '$TARGET', which is not a git checkout"
TARGET=$(git -C "$TARGET" rev-parse --show-toplevel)

meta=$(cd "$TARGET" && gh repo view --json nameWithOwner,hasIssuesEnabled,viewerPermission 2>/dev/null) \
  || die "$TARGET is not a GitHub repo gh can read"
REPO=$(echo "$meta" | jq -r .nameWithOwner)
[ "$(echo "$meta" | jq -r .hasIssuesEnabled)" = true ] || die "$REPO has issues disabled"
case "$(echo "$meta" | jq -r .viewerPermission)" in
  ADMIN|MAINTAIN|WRITE) ;;
  *) die "no write access to $REPO; never open issues on a third-party repo" ;;
esac

owner=$(basename "$TARGET" | sed 's/-oracle$//')
day=$(TZ='Asia/Bangkok' date +%-d%b-%a%Y | tr '[:upper:]' '[:lower:]')
# herdr: a name starts with a lowercase letter; lowercase, digits, - or _ only; 1-32 chars
agent_name=$(printf '%s' "$SLUG-$owner" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_\n-' '-')
[ ${#agent_name} -le 32 ] || agent_name=${agent_name:0:32}
sender_repo=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
sender=$(basename "$sender_repo" | sed 's/-oracle$//')
label=$(cd "$TARGET" && gh label list --limit 200 --json name -q '.[].name' 2>/dev/null \
  | grep -ix "oracle:$owner" | head -1 || true)

# ── the brief (the issue body) ───────────────────────────────────────────────
inc_block=""
if [ -n "$INCUBATE" ]; then
  inc_repo=${INCUBATE#*/}
  if [ "$ENGINE" = claude ]; then
    inc_block="## First step — incubate
Run \`/incubate $INCUBATE\`. It clones the repo with ghq and links it under \`ψ/incubate/\`."
  else
    inc_block="## First step — incubate
Codex has no Claude skills, so do what \`/incubate\` does by hand:
\`\`\`bash
ghq get -p github.com/$INCUBATE
mkdir -p ψ/incubate && ln -sfn \"\$(ghq root)/github.com/$INCUBATE\" ψ/incubate/$inc_repo
\`\`\`
Read and change code inside \`ψ/incubate/$inc_repo\`. Do not commit to $INCUBATE directly; open a PR there."
  fi
fi

BODY=$(cat <<EOF
## Goal
$TASK

## Context
Sent by **$sender** (\`$sender_repo\`, herdr pane \`${HERDR_PANE_ID:-?}\`) to **$owner** via \`/herdr-send\`.
Engine for this run: **$ENGINE**.

$inc_block

## How to work
1. Read this issue and its comments first: \`gh issue view <N> --repo $REPO --comments\`.
2. Understand the context (\`/trace\`, \`/dig\` or plain reading) and write a short plan as a comment here before changing code.
3. Work only in this worktree and commit on its branch. Do not push to main, force-push or merge.
4. Report on this issue: commit hashes, files changed, what is blocked, open questions.

## Done when
- [ ] The goal above is met, or the blocker is written up here
- [ ] A final report comment with commits and files

---
Opened by $sender (AI) via /herdr-send
EOF
)

if [ "$DRY" = 1 ]; then
  cat <<EOF
DRY RUN — nothing created
  oracle     : $ORACLE -> $TARGET ($REPO)
  issue      : new issue in $REPO${label:+, label $label}
  worktree   : $TARGET/wt/$SLUG-$owner-issue<N>-$day   (base $BASE)
  engine     : $ENGINE  ->  $CMD
  agent name : $agent_name
  incubate   : ${INCUBATE:-none}
----- issue body -----
$BODY
EOF
  exit 0
fi

# ── 1. issue ─────────────────────────────────────────────────────────────────
title="$SLUG: $(echo "$TASK" | head -1 | cut -c1-80)"
ISSUE_URL=$(cd "$TARGET" && gh issue create --repo "$REPO" --title "$title" \
  ${label:+--label "$label"} --body-file - <<<"$BODY") || die "gh issue create failed"
ISSUE=${ISSUE_URL##*/}
echo "issue    : $ISSUE_URL"

# ── 2. worktree (same steps as /herdr-wt) ────────────────────────────────────
name="$SLUG-$owner-issue$ISSUE-$day"
dest="$TARGET/wt/$name"
[ ! -e "$dest" ] || ask "$dest already exists — read it (git log, lock reason) before reusing"
SPACE=$(herdr worktree create --cwd "$TARGET" --branch "$name" --base "$BASE" --path "$dest" --no-focus \
  | jq -r '.result.workspace.workspace_id // empty')
[ -n "$SPACE" ] || die "herdr worktree create failed for $dest (issue $ISSUE_URL is open)"
git -C "$TARGET" worktree lock --reason "herdr|$(whoami)@$(hostname -s)|$(date -Iseconds)|$SLUG|#$ISSUE|herdr-send" "$dest"
[ -f "$dest/.envrc" ] || [ ! -f "$TARGET/.envrc" ] || cp -a "$TARGET/.envrc" "$dest/.envrc"
if [ -f "$dest/.envrc" ]; then
  (cd "$dest" && tok=$(maw token resolve 2>/dev/null) && [ -n "$tok" ] && maw token use "$tok" >/dev/null 2>&1) \
    || echo "warn     : maw token use failed in $dest; check direnv before trusting the agent's token" >&2
fi
lab=""
if [ -d "$dest/ψ" ]; then
  lab="ψ/lab/$SLUG"; mkdir -p "$dest/$lab"
  if git -C "$dest" check-ignore -q "$lab/x"; then
    printf '!%s/\n' "$lab" >> "$dest/.gitignore"
    git -C "$dest" check-ignore -q "$lab/x" && echo "warn     : $lab is still gitignored; fix .gitignore by hand" >&2
  fi
fi
echo "worktree : $dest (space $SPACE)"

# The space's first pane: find it by cwd.
PANE=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  PANE=$(herdr pane list | jq -r --arg d "$dest" '.result.panes[] | select(.cwd == $d) | .pane_id' | head -1)
  [ -n "$PANE" ] && break
  sleep 1                           # the pane registers asynchronously
done
[ -n "$PANE" ] || die "no pane found in $dest (space $SPACE, issue $ISSUE_URL)"

gh issue comment "$ISSUE" --repo "$REPO" --body "Workspace
- branch: \`$name\`
- path: \`wt/$name\`
- herdr space: \`$SPACE\` · pane: \`$PANE\`
- agent: \`$agent_name\` ($ENGINE)
- lab: \`${lab:-none (no ψ/ in this repo)}\`" >/dev/null

# ── 3. agent ─────────────────────────────────────────────────────────────────
# A throwaway command first: the pane's shell started before maw token use trusted the
# path, and only a fresh prompt makes direnv load it (/herdr-wt, "pane run is not enough").
herdr pane run "$PANE" 'echo "TOK=${CLAUDE_TOKEN_NAME:-none}"' >/dev/null
herdr pane wait-output "$PANE" --match 'TOK=' --timeout 40000 >/dev/null 2>&1 || true
herdr pane run "$PANE" "$CMD" >/dev/null

ready=""
if [ "$ENGINE" = claude ]; then
  for _ in $(seq 1 24); do                            # up to ~120 s; direnv alone can take 40 s
    sleep 5
    st=$(herdr pane get "$PANE" 2>/dev/null | jq -r '.result.pane | "\(.agent // "none") \(.agent_status // "-")"')
    case "$st" in none*|"") ;; *" idle") ready=$st; break ;; esac
  done
  [ -n "$ready" ] || die "claude did not come up idle in $PANE — herdr pane read $PANE --source visible --lines 20"
else
  # codex / omx: herdr reports them "working" even while they wait at their prompt (measured
  # 2026-10-03, omx --direct, gpt-6-astra), so agent_status never says idle and an idle wait
  # dies after 120 s with the agent ready. Wait for the prompt itself — or omx's hooks trust
  # gate — on the VISIBLE screen: a history read (--source recent) makes an agent redraw.
  herdr pane wait-output "$PANE" --regex 'Ask Codex to do anything|Hooks need review' --source visible --timeout 150000 >/dev/null 2>&1 \
    || die "$ENGINE did not reach its prompt in $PANE within 150 s — herdr pane read $PANE --source visible --lines 20"
  if herdr pane read "$PANE" --source visible --lines 30 2>/dev/null | grep -q "Hooks need review"; then
    echo "omx stopped at its hooks trust gate in $PANE. That is the human's call:" >&2
    echo "  1 review / 2 trust all / 3 continue without — then re-send the brief (see issue $ISSUE_URL)" >&2
    exit 2
  fi
  ready="$ENGINE at its prompt"
fi
herdr agent rename "$PANE" "$agent_name" >/dev/null 2>&1 || echo "warn     : could not name the agent $agent_name" >&2

# ── 4. brief from the issue ──────────────────────────────────────────────────
BRIEF="Your task is GitHub issue #$ISSUE in $REPO: $ISSUE_URL
Read it first: gh issue view $ISSUE --repo $REPO --comments
It is your full brief. Report progress as comments on that issue.
Work only in this worktree, commit on this branch; no push to main, no merge.
— sent by $sender via /herdr-send"
herdr agent prompt "$PANE" "$BRIEF" >/dev/null || die "brief not delivered to $PANE; read the pane before re-sending"

cat <<EOF
OK
  issue  : $ISSUE_URL
  branch : $name
  space  : $SPACE   pane: $PANE   agent: $agent_name ($ready)
  engine : $ENGINE
EOF
