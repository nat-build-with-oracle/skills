---
name: herdr-idea
description: "Start a numbered lab that exists on disk — auto-increments NN from ψ/lab, cuts a worktree at <repo>/wt/NN-slug, locks it, opens its own herdr space, and scaffolds ψ/lab/NN-slug/README.md with a charter-lite whose Who: line names the worktree that was actually created. Self-contained; works without any justfile recipe. Use when the user says \"herdr idea\", \"new lab with a worktree\", \"start lab NN\", or wants a lab that comes with a body rather than only a README. Do NOT use for the prism+grill interview that decides WHAT the lab is (use /lab-idea first, then this), for a plain task worktree (use /herdr-wt), or for another oracle's topic (use /herdr-incubate)."
argument-hint: "<slug> [base-ref]"
---

# /herdr-idea — a lab with a body

`/lab-idea` scaffolds `ψ/lab/NN-slug/README.md` and stops. Its charter-lite then names a
worker and a worktree that **nothing creates**. This makes the worktree first, so the
charter can state what is true.

## Run it

```bash
SLUG=liveness-probe; BASE=HEAD
repo=$(git rev-parse --show-toplevel)
test -d "$repo/ψ" || { echo "REFUSING: not an oracle repo (no ψ/)"; exit 1; }

# Derive NN from disk, never from memory. Never reuse a deleted number.
last=$(ls -1 "$repo/ψ/lab" 2>/dev/null | grep -oE '^[0-9]{2}' | sort -n | tail -1 || true)
nn=$(printf "%02d" $((10#${last:-0} + 1)))
name="$nn-$SLUG"
dest="$repo/wt/$name"
test ! -e "$dest" || { echo "REFUSING: already exists: $dest"; exit 1; }
test ! -e "$repo/ψ/lab/$name" || { echo "REFUSING: lab dir exists"; exit 1; }

herdr worktree create --cwd "$repo" --branch "$name" --base "$BASE" --path "$dest" --no-focus \
  | python3 -c "import json,sys; d=json.load(sys.stdin)['result']; print('space', d['workspace']['workspace_id'], 'pane', d.get('root_pane',{}).get('pane_id','?'))"
git -C "$repo" worktree lock --reason "herdr|$(whoami)@$(hostname -s)|$(date -Iseconds)|lab $name" "$dest"

mkdir -p "$dest/ψ/lab/$name"
cat > "$dest/ψ/lab/$name/README.md" <<EOF
# $name

> One line: what this lab proves.

## Charter-lite

- **Who**: agent in \`wt/$name\` (branch \`$name\`) — this worktree, which EXISTS
- **Off-limits**: <paths/repos this lab must never touch; "none" if truly none>
- **Done-when**: <one line>
- **Verify**: \`<exact command that proves done-when>\`
- **Escalate**: before any push, merge, or deploy
EOF
echo "$dest/ψ/lab/$name/README.md"
```

Then staff it:

```bash
herdr agent start <NN-slug> --kind claude --pane <pane>
```

**In `<org>/<oracle>-oracle` only**, wrapped as `just herdr-idea <slug> [base]`.

## Why this exists — the failure it prevents

On 2026-09-14 two labs' charters named worktrees `agents/01-jsonl-watch` and
`agents/01-jsonl-liveness`. Both **already existed** with real work on them — one was 32
commits deep with a full app, 124 files. Dispatching from the issue text alone, the
charter line was read as legacy naming to be modernised rather than as a pointer to live
work, and both labs were rebuilt from scratch on duplicate branches.

A charter that names a worktree nobody created teaches you to discount it. When the
worktree is made first, the `Who:` line is a fact.

**So: before creating anything, check whether the lab already has a body.**

```bash
git -C <repo> worktree list | rg '<slug>'
git -C <repo> branch -a | rg '<slug>'
```

## Naming: `wt/NN-slug`, no date

Unlike `/herdr-wt`, no date is appended. A lab's `NN-slug` is already its identity and a
lab is long-lived — same reasoning as `/herdr-incubate ... plain`. The number comes from
disk every time:

```bash
last=$(ls -1 ψ/lab | grep -oE '^[0-9]{2}' | sort -n | tail -1)
```

Dirs without an `NN-` prefix (older, manual) are ignored by the grep — do not count them
and do not rename them. Never reuse a deleted number.

## Where it sits among the verbs

| what you want | verb |
|---|---|
| decide WHAT the lab is (prism + grill) | `/lab-idea` |
| a numbered lab **with** a worktree and space | `/herdr-idea` |
| a plain task worktree | `/herdr-wt <slug>` |
| another oracle's topic, from here | `/herdr-incubate <oracle>` |
| a bypass-approvals pair beside you | `/herdr-buddy` |

`/lab-idea` then `/herdr-idea` is the intended pair: interview first, body second.

## Cleanup

```bash
git -C <repo> worktree unlock wt/<NN-slug>       # lock blocks removal on purpose
herdr worktree remove --workspace <wsid> --force
git -C <repo> worktree prune
```

Check first — a lab worktree is where the work IS:

```bash
git -C wt/<NN-slug> status --short
git -C wt/<NN-slug> rev-list --count origin/main..HEAD
```

## Related

- `/lab-idea` — the prism+grill pass that decides the lab's content
- `/herdr-wt` — the naming convention, the lock semantics, and the worktree traps
- `/herdr-incubate`, `/herdr-buddy`
