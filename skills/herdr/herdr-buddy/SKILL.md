---
name: herdr-buddy
description: Split the current herdr pane and drop a bypass-approvals buddy agent beside you — omx (--direct --madmax), omp (--approval-mode=yolo), or claude (--dangerously-skip-permissions). Self-contained; works without any justfile recipe. Refuses to run in a main checkout, since a buddy that never asks can run anything where other agents are working. Use when the user says "buddy", "bring a buddy", "omx beside me", "madmax", "give me a yolo pair", or wants a second agent adjacent in the same space. Do NOT use to open a new space for a repo (use /herdr-bring), to cut a worktree (use /herdr-wt), or to start a normal approval-respecting agent (plain `herdr agent start --kind claude`).
argument-hint: "[omx|omp|claude] [label]"
---

# /herdr-buddy — a pair that never asks

⚠️ **Every flavour bypasses approvals.** That is the whole point — a buddy works without
stopping to confirm — and it means the buddy can run anything reachable from its cwd.
Only ever in a worktree.

## Run it

```bash
FLAVOR=omx; LABEL=""      # omx | omp | claude

case "$FLAVOR" in
  omx)    cmd="OMX_AUTO_UPDATE=0 omx --direct --madmax"; ready="Ask Codex" ;;
  omp)    cmd="omp --approval-mode=yolo";                ready="" ;;
  claude) cmd="claude --dangerously-skip-permissions";   ready="" ;;
  *)      echo "REFUSING: flavor must be omx|omp|claude"; exit 1 ;;
esac
label="${LABEL:-$FLAVOR}"

# Main checkout = git-dir equals git-common-dir (both the literal '.git').
repo=$(git rev-parse --show-toplevel)
if [ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ]; then
  echo "REFUSING: $repo is a main checkout — cut a worktree first (/herdr-wt <slug>)"; exit 1
fi

pane=$(herdr pane split --current --direction right \
  | python3 -c "import json,sys; d=json.load(sys.stdin)['result']; print(d.get('pane',d).get('pane_id'))")
herdr pane run "$pane" "$cmd"
if [ -n "$ready" ]; then
  herdr pane wait-output "$pane" --match "$ready" --timeout 60000 >/dev/null \
    || { echo "!! never saw '$ready' in 60s — herdr pane read $pane --source visible --lines 20"; exit 1; }
else
  sleep 6
fi
herdr agent rename "$pane" "$label" >/dev/null 2>&1 || true
echo "$pane -> $label ($FLAVOR) — approvals BYPASSED"
```

**In `<org>/<oracle>-oracle` only**, wrapped as `just herdr-buddy [flavor] [label]`.

## Flavours

| flavour | command | readiness |
|---|---|---|
| `omx` (default) | `omx --direct --madmax` — bypass Codex approvals AND sandbox | waits for `Ask Codex` |
| `omp` | `omp --approval-mode=yolo` | 6s sleep |
| `claude` | `claude --dangerously-skip-permissions` | 6s sleep |

`OMX_AUTO_UPDATE=0` on omx is **mandatory**, not tidiness: a fresh worktree has no
`.envrc`, omx self-updates, drops to a shell or an update menu, and any standing contract
is lost before you notice.

`--direct` launches the interactive leader without OMX's own tmux/HUD management — herdr
is already the multiplexer, so letting omx start a second one nests two of them.

## The main-checkout guard, and why it is written this way

Test whether **git-dir equals git-common-dir**:

```bash
[ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ]   # true = MAIN checkout
```

| | `--git-dir` | `--git-common-dir` |
|---|---|---|
| main checkout | `.git` | `.git` |
| linked worktree | `<repo>/.git/worktrees/<name>` | `<repo>/.git` |

**Do not** compare `--git-dir` to `"$repo/.git"`. It returns a **relative** path, so that
comparison never matches, the guard passes, and a madmax buddy launches in the shared
checkout. That happened for real on 2026-09-14 — the buddy came up in main <oracle>-oracle
alongside other working agents and had to be closed by hand. The guard failed *open*,
which is the dangerous direction: a broken guard that refuses is noisy, a broken guard
that permits is silent.

## Cleanup

A buddy is a pane, not a worktree — closing it is enough:

```bash
herdr pane close <pane>
```

Check what it was doing first; a madmax buddy may have uncommitted work:

```bash
herdr pane read <pane> --source recent-unwrapped --lines 60
git -C <worktree> status --short
```

## Known gap

Only `omx` has a real readiness signal (`Ask Codex`). `omp` and `claude` fall back to a
flat 6-second sleep, so on a cold pane — direnv alone can take ~40s — the rename can fire
before the agent exists and silently no-op (`|| true`). The pane still works; it is just
unnamed. If you find a stable first-output marker for either, replace the sleep with
`wait-output`.

## Related

- `/herdr-wt` — cut the worktree a buddy is allowed to live in
- `/herdr-incubate` — a worktree targeting another oracle
- `/herdr-bring` — land an oracle's own repo as its own space
- `herdr` (global skill) — panes, splits, agents, prompting
