---
name: herdr-wt
description: Create a git worktree for a distinct piece of work in ANY repo, placed at <repo>/wt/<oracle>-<slug>-<date> and opened as its own herdr space. Self-contained — works without any justfile recipe. Use when starting work that deserves its own branch and checkout, a parallel agent's workspace, or when the user says "make a worktree", "start work on X", "spin up a branch for this", "new wt dir". Also the reference for WHY the naming is oracle-slug-date and what breaks if that changes. Do NOT use to move an existing session into herdr (use /herdr-bring), to fork a session in place (`herdr` skill covers forking), or to spawn an isolated OMX/Codex worker (use /isolate-worktree).
argument-hint: "<slug> [base-ref]"
---

# /herdr-wt — worktree per piece of work

Works in any repo on any machine. Requires `herdr` on PATH and a git repo; nothing else.

## Run it

Copy-paste, substituting the slug (and optionally a base ref):

```bash
SLUG=herdr-bring; BASE=HEAD
repo=$(git rev-parse --show-toplevel)
day=$(TZ='Asia/Bangkok' date +%-d%b-%a%Y | tr '[:upper:]' '[:lower:]')
owner=$(basename "$repo" | sed 's/-oracle$//')
name="$owner-$SLUG-$day"
dest="$repo/wt/$name"
test ! -e "$dest" || { echo "already exists: $dest"; exit 1; }
herdr worktree create --cwd "$repo" --branch "$name" --base "$BASE" --path "$dest" --no-focus \
  | python3 -c "import json,sys; print('space', json.load(sys.stdin)['result']['workspace']['workspace_id'], '->', sys.argv[1])" "$name"
git -C "$repo" worktree lock --reason "herdr|$(whoami)@$(hostname -s)|$(date -Iseconds)|$SLUG" "$dest"
direnv allow "$dest"   # see below — a new worktree path is untrusted by direnv
echo "$dest"
```

The lock is borrowed from `/incubate` (same `tool|who|when|why` field order, so one parser
reads both). It is **not** security — it is a "do not auto-clean me" flag, and it earns its
keep twice, both verified 2026-09-14:

- `git worktree prune` leaves it registered **even after the directory is deleted**.
  Without a lock, prune is exactly what silently drops a worktree — and prune is the
  command recovery docs tell people to run.
- `git worktree remove --force` refuses it outright:
  `fatal: cannot remove a locked working tree` (needs `-f -f`).

The lock reason is also the only per-worktree metadata that survives `kill -9`; it lives at
`<repo>/.git/worktrees/<name>/locked`.

Produces, for slug `herdr-bring` in `<oracle>-oracle` on 14 Sep 2026:

| | |
|---|---|
| branch | `neo-herdr-bring-14sep-mon2026` |
| path | `<repo>/wt/neo-herdr-bring-14sep-mon2026` |
| herdr | its own space, `--no-focus` |

**In `<org>/<oracle>-oracle` only**, the same thing is wrapped as `just herdr-wt <slug> [base]`.
No other repo has that recipe — verified across the full `ghq list`, 1 of N repos — so
use the inline block everywhere else.

Then put an agent in it (the pane comes up as a bare shell):

```bash
herdr agent start <name> --kind claude --pane <pane>
```

## Before first use on a new machine — one prerequisite

`wt/` is already ignored **fleet-wide** via `~/.config/git/ignore` (added 2026-09-14).
Git reads that path by XDG default when `core.excludesFile` is unset, so no per-repo
`.gitignore` edit is needed — one line covers every repo on the machine. Verify on a new
machine before trusting it:

```bash
git check-ignore -v wt/x || printf '/wt/\n' >> ~/.config/git/ignore
```

The leading slash anchors it to each repo's root, so it does not shadow nested `wt/`
directories such as incubate's `ψ/incubate/<slug>/wt/`.

**`dig.py` must fold `wt`** or every worktree reports as its own phantom project in
`/dig`. Check and patch the global skill file:

```bash
rg -n 're\.sub' ~/.claude/skills/dig/scripts/dig.py | rg 'wt'
# want: re.sub(r'-(wt|agents)-.*$', '', base)
# NOT:  re.sub(r'-wt-\d+.*$', '', base)
```

The original required a **digit** right after `wt-`, so it matched `wt-1-white` but not
`wt-herdr-14sep-mon2026`. Session dirs then fall through to `clean.split('-')[-1]` and
report as a phantom repo — exactly why `homelab-agents-1-gpu` showed up as repo `gpu`.
Applied on m5 2026-09-14; **white still needs it**.

## Why the name is shaped this way

Decided against the obvious alternatives, with evidence. Do not "fix" them back without
re-running the same checks.

**Date goes LAST.** maw's own day repos are date-first, so date-first looks consistent.
Two reasons it isn't, for worktrees:

1. *Date-first does not sort chronologically.* maw writes single-digit days unpadded
   (`1sep-tue2026` … `9sep-tue2026`), so `9sep` sorts **after** `10sep`. Verify:
   `printf '%s\n' 9sep-tue2026-a 10sep-wed2026-b | sort`
2. *Trailing it groups by topic* — every `herdr-*` worktree lands together instead of
   scattering across months.

Not an inconsistency with maw: its date-first names are **day repos** where the date is
the identity. A worktree is **task-scoped** — the task is the identity, date is metadata.

**Oracle prefix** because herdr's sidebar lists spaces FLAT and truncates. A bare
`herdr-14sep-mon20…` gives no clue which oracle owns it once several have worktrees open.
`<oracle>-oracle` → `neo`; a non-oracle repo keeps its basename (`homelab` → `homelab-…`).

**Location `<repo>/wt/`, not `~/.herdr/worktrees/`.** herdr's `worktrees.directory` is a
single global root it appends `<repo>/<branch>` to — it cannot express "relative to the
current repo". `--path` is the only lever. `wt` also matches the convention already
dominant on disk (`homelab-wt-1-white`, `wt-2-cftunnel`, `wt-statusline`).

## Always `direnv allow` the new worktree

A worktree is a **new path**, so direnv's allow-list has never seen it — even
though the parent repo is trusted and `.envrc` is the identical file. Until you
allow it, direnv refuses to load and every pane opened there starts **without**
the repo's environment.

Measured 2026-09-15 on `wt/neo-herdr-14sep-mon2026`: the pane showed

```
direnv: error …/.envrc is blocked. Run `direnv allow` to approve its content
```

and `direnv status` reported `Found RC allowed 0` while the *loaded* RC was a
different repo's entirely. Agents spawned into that worktree therefore ran
without `CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_TOKEN_NAME`, `ORACLE_URL` and
`ORACLE_PROJECT` — a different environment than the shell that created them,
which is exactly the kind of difference that surfaces later as an auth failure
nobody can reproduce.

It is a trust decision, so read the file before approving it — `.envrc` here
shells out to `pass show` for a real token. Verify without starting a shell:

```bash
direnv exec "$dest" bash -c 'echo "$CLAUDE_TOKEN_NAME $ORACLE_PROJECT"'
```

## Cleanup

Unlock first — the lock blocks removal on purpose:

```bash
git -C <repo> worktree unlock wt/<name>
herdr worktree remove --workspace <wsid> --force
```

Removes the checkout AND deregisters from `git worktree list` in one step. Check first:

```bash
git -C wt/<name> status --short                  # dirty?
git -C wt/<name> rev-list --count main..HEAD     # unmerged commits?
```

If the worktree was ever **moved**, herdr's record keeps the OLD path — it deletes the
space but leaves the real checkout behind. Finish with git:

```bash
git -C <repo> worktree remove wt/<name>
```

## Trap: never `git worktree move` a worktree with a live agent in it

A running agent pins its **cwd and Claude project dir at startup**. git and herdr both
relocate cleanly — git metadata updates, herdr's pane cwd follows — but the agent inside
cannot follow. It points at a vanished path and silently falls back to the main repo.

The tell is quiet: `pwd` inside the agent returns the **main repo**, and its status line
reads `main@<sha>` instead of the worktree branch.

A healthy worktree agent shows path, branch, and 🌳:

```
📁 <org>/<oracle>-oracle/wt/neo-herdr-14sep-mon2026
   neo-herdr-14sep-mon2026@31d3ceb 🌳
```

**Rule**: move while empty, or restart the agent after. Restart is cheap — `/exit` (two
`ctrl+c` did NOT exit it), then `herdr agent start` again; the pane cwd is already right.

## Trap: worktree identity lives on the SPACE, not the pane

From herdr's source, `src/workspace.rs:196` — `worktree_space` is a field on `Workspace`.
`pane.rs` and `tab.rs` contain **zero** `worktree` references.

Moving a worktree's pane into another space's tab strips its worktree identity: it loses
the indented nesting and inherits the destination's branch label. `herdr worktree list`
then shows `open_workspace_id: -`. Recover:

```bash
herdr worktree open --cwd <repo> --path <worktree-path> --label <name> --no-focus
```

Adjacency and worktree identity are mutually exclusive — a model limit, not a missing flag.

## Trap: don't branch in a shared checkout

`git checkout -b` in a repo other agents are working in moves **all of them** onto your
branch. That is what this skill exists to avoid — use a worktree for branch work,
including your own PR branches.

## Boundary with `/incubate --wt`

Both cut worktrees; they do not merge and neither calls the other. The split is
**ownership of the repo**, and it decides where the checkout may legally live.

| | `/incubate --wt` | `/herdr-wt` |
|---|---|---|
| repo | someone else's, cloned via `ghq` | an oracle repo you own |
| worktree path | `$XDG_STATE_HOME/incubate/worktrees` (outside) | `<repo>/wt/` (inside) |
| branch | `incubate/<slug>` | `<oracle>-<slug>-<date>` |
| lock | always, at creation | always, at creation (adopted from incubate) |
| opens a herdr space | no | yes |

**Why incubate must stay outside and we may stay inside** — from incubate's own notes:
`ghq list` decides "is this a repository" by `stat`-ing `<dir>/.git`, and a linked
worktree's `.git` is a *file*, not a directory. A worktree under the ghq root therefore
registers as a phantom repo. Incubate clones *into* the ghq root, so it has no choice but
to place bodies elsewhere. Our `wt/` sits inside an oracle repo that is already a single
ghq entry, and it is gitignored, so nothing enumerates it. Same constraint, two correct
answers — do not "unify" them onto one path.

**Picking one**: if you would open a herdr space for it, it is `/herdr-wt`. If it is a
third-party repo you are contributing to, it is `/incubate`.

## Related

- `/herdr-bring` — land an existing maw handle into a herdr space (project skill in <oracle>-oracle)
- `herdr` (global skill) — the CLI reference: panes, agents, forking, prompting
- `/isolate-worktree` — different tool: spawns an isolated OMX/Codex worker
