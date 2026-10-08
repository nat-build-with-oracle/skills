---
name: herdr-clean-up-sync
description: Tidy the herdr sidebar on one or more machines — close finished (✓) agents and idle shells whose work is merged or pushed, remove their worktrees through herdr so the sidebar and git agree, prune worktrees whose folder is gone, close spaces pointing at missing folders, and fast-forward checkouts that are only behind (the sidebar's `main ↓130`). Always shows the plan and asks before anything is closed or removed. Use when the user says "clean up herdr", "clean up the sidebar", "sync", "too many ✓", "close the done ones", "everything is ↓", or /herdr-clean-up-sync. Do NOT use to check whether ONE session is safe to close (use /herdr-done), to create worktrees (/herdr-wt), or to move sessions between machines (/herdr-bring).
argument-hint: "[--host <ssh>]... [--all]"
---

# /herdr-clean-up-sync — tidy the sidebar, then catch up

> **Needs `fleet`.** This skill drives the `fleet` CLI from
> [nat-build-with-oracle/herdr-fleet](https://github.com/nat-build-with-oracle/herdr-fleet).
> Install: `git clone https://github.com/nat-build-with-oracle/herdr-fleet.git && cd herdr-fleet && mkdir -p ~/.local/share ~/.local/bin && ln -sfn "$PWD" ~/.local/share/herdr-fleet && ln -sfn ~/.local/share/herdr-fleet/fleet.ts ~/.local/bin/fleet && bun install`
> then check with `fleet help | head -3`.

One pass, two halves. **Clean up** removes what is finished; **sync** fast-forwards what
is behind. Both run on `fleet` (`worktrees.ts` in herdr-fleet). Every command below prints a plan until
`--go` is added, and nothing is closed until the human has picked it.

```
fleet audit  [--host H] [--idle-agents] [--idle-shells] [--min-age N] [--json]
fleet clean  [--host H] [--pick wt1,wt2] [--tier A,B,C] [--idle-agents] [--idle-shells] [--go]
fleet sync   [--host H] [--all] [--go]
```

No `--host` = this machine. `--host my-server` runs the same code on that machine
over ssh; it needs bun, git, gh, and ghq there, but nothing from fleet.

**Scope is the whole machine by default.** With no `--repo` and no `--pick`, `audit` and
`clean` walk every repo in `ghq list -p` (1278 on m5, 2026-10-08), and "Safe now" below
acts on every tier A/B/C worktree with no agent: that includes **pushed but unmerged (C)
work folders in every repo**. Losing nothing in git terms is not the same as "done".

## 0. One worktree only (the usual case after one session)

When the human asks to retire ONE worktree, scope both flags. `--repo` filters the repo
list by substring; `--pick` turns every other row into `K "not picked"`:

```bash
WT=~/.herdr/worktrees/<oracle>-oracle/worktree-calm-meadow-eea9     # full path
fleet audit --repo <org>/<oracle>-oracle --pick "$WT" --no-fetch          # 9 rows, 8 K
python3 ~/.claude/skills/herdr-clean-up-sync/tombstone.py "$WT"           # step 3b, dry run
fleet clean --repo <org>/<oracle>-oracle --pick "$WT" --idle-agents        # plan
fleet clean --repo <org>/<oracle>-oracle --pick "$WT" --idle-agents --go   # act
```

- **Run it from a pane OUTSIDE that worktree**, after its agent has finished. A working
  agent keeps the row at `K` ("agent working"), and removing the folder under a live
  session breaks it. `--idle-agents` quits the idle agent with ctrl-c first.
- **The whole space goes**, every pane in it (the 2026-10-08 audit listed
  `panes: <pane>,<pane>`, the agent and its `run` tab).
- **What goes with it.** `.envrc`, `.DS_Store` and `._*` count as junk
  (`worktrees.ts:49,71`): a modified `.envrc` reads `dirty: 0` and is deleted with the
  worktree. Any other uncommitted file makes it `SKIP uncommitted`. Gitignored data under
  50 MB (`IGNORED_CAP`) is deleted too, so copy anything you want out of `.tmp/` first;
  over 50 MB the worktree is kept.

## 1. Survey (read-only, per machine)

```bash
fleet audit --idle-agents --idle-shells --min-age 0 --json > .tmp/cleanup-<host>.json
fleet sync --json > .tmp/sync-<host>.json          # plan only
```

`--min-age 0` shows everything that is safe on the git side, so the human sees the ✓ agents
touched today too. Rows come back in tiers:

| tier | means | removing it loses |
|---|---|---|
| A | worktree folder gone, or a herdr space on a missing folder | nothing |
| B | merged (in the default branch, or a merged PR whose head IS this HEAD), clean | nothing |
| C | pushed, clean, not merged | nothing; the branch stays |
| D | uncommitted work or local-only commits | the work, unless rescued first |
| K | an agent is **working/blocked** in it, or not picked | kept, never touched |

For every row that has an agent, read what it last said before offering it:

```bash
herdr pane read <pane> --source recent-unwrapped --lines 40 | tail -12
```

✓ in the sidebar means the agent **finished its turn**, not that the task is finished. An
agent that ended on a question ("A or B?"), a plan waiting for approval, or "want me to
merge?" is waiting on the human. Mark it **waiting**, and never offer it as done.

## 2. Show the plan, then ask

Present one table per machine, grouped:

- **Safe now**: A, plus B/C with no agent. Nothing is lost.
- **Done agents**: B/C with an idle ✓ agent whose last output reads finished. Quitting it keeps its
  transcript in `~/.claude/projects`, and `/herdr-bring` or `claude --resume` can revive it.
- **Waiting on you**: idle agents whose last output is a question. Listed, not offered.
- **Unsaved work (D)**: listed with what is dirty. Offer the rescue separately (step 4).
- **Behind (sync)**: `would ff` rows, and the SKIP reasons (modified, diverged, no upstream).

Then AskUserQuestion (multiSelect): *Safe now* (recommended), *Done agents*, *Sync
fast-forwards*, *Rescue D to draft PRs*. Put the row COUNT and the repos in *Safe now*'s
description (`removes 23 worktrees in 11 repos`); a label alone hides that it is
machine-wide. For a long "Done agents" list, let the user
drop names in "Other".

## 3. Act on exactly what was picked

```bash
# safe now: A/B/C, no agents
fleet clean [--host H] --idle-shells --go
# done agents: only the named worktrees; each ✓ agent is quit with ctrl-c first,
# then the space goes through `herdr worktree remove` so the sidebar agrees with git
fleet clean [--host H] --pick <wt1,wt2,...> --go
# behind
fleet sync [--host H] --go
```

`--pick` switches off the age rule for those rows only. It still re-checks everything
just before acting: a working agent, new edits, or new local commits turn the row into a
SKIP.

## 3b. Tombstone first (ceasing is not deleting)

Removing a worktree ends its function. It must not end its record. Before any `--go` that
removes a tier B/C worktree (or a done agent's worktree), write its tombstone:

```bash
python3 ~/.claude/skills/herdr-clean-up-sync/tombstone.py <worktree-path>             # dry run
python3 ~/.claude/skills/herdr-clean-up-sync/tombstone.py <worktree-path> --write --reason "merged PR #12"
```

It records what the worktree was (branch, born, own commits), why it ended (merged PR, or
commits already in main), the successor (PR url or `main@sha`), and where the record lives
(branch kept, agent session ids with transcript paths). It writes to
`<main checkout>/ψ/memory/tombstones/<date>_<label>.md`, or `~/.herdr/tombstones/<repo>/`
when the repo has no ψ. It never overwrites a tombstone and never removes anything.

Read its `BLOCKER:` lines before removing:

- uncommitted or untracked files: they are not in any commit, so removal loses them. Rescue or
  look at them first (step 4).
- HEAD not in main and no merged PR: it is not merged, so it is not a ceasing worktree.
- LOCKED: `wtui` locks every worktree it cuts. Unlock deliberately, do not force.

`/herdr-tree` shows the phase that tells you which rows to do this for: `cease` rows are
ready. `stand!` rows (main moved on, or commits landed after the PR merged) are not.

**Why:** a moved or removed thing that keeps speaking as if it were alive, with no death
date and no successor, is a record that has lost its chain (the "archive the body, drop the
chain" case found 2026-08-22: 33 of 39 archived skills had neither). The tombstone is the chain.

## 4. Unsaved work (only if asked)

```bash
fleet clean [--host H] --pick <wt,...> --tier D --pr --go
```

This commits to `rescue/<wt>`, pushes, opens a signed draft PR, and removes the worktree. Built-in
guards:

- `.codex/`, `.env*`, shell snapshots and credentials are never committed.
- If the staged diff contains anything key-like, it stops before pushing.
- Repo hooks never run.
- A file over 10 MB keeps its worktree, and a rescue over 50 MB in total is refused.

**Before any `--pr` in a public repo**, list what is about to be committed:

```bash
git -C <wt> status --porcelain -uall | head -40
```

A 2026-09-24 run by hand pushed Codex session logs into public PRs. Closed PRs keep their
commits on GitHub, and only GitHub Support can purge them.

## 5. Record and report

```bash
fleet snapshot --commit        # the fleet history sees the change (local machine)
```

Report per machine: before and after worktree counts, spaces closed, agents quit (with the
pane id and session id so they can be revived), fast-forwards (`↓N → sha`), and every
SKIP with its reason. Name anything left for the human: waiting agents, D rows, diverged
checkouts.

## Traps

- **`fleet <cmd> --help` is not help.** There is no help flag; unknown flags are ignored,
  so `fleet clean --help` ran a full-machine `clean` plan (2026-10-08, stopped at repo
  445/1278). Without `--go` it changes nothing, but never type a flag to "see the usage".
  The usage is the header comment of `worktrees.ts` in herdr-fleet.

- **A space can hold an agent in a second tab or pane.** 2026-10-05: atlas had been moved into another
  space as its own tab; closing that space would have killed it. Before closing a space, list ALL its panes
  in ALL tabs (`herdr pane list --workspace W`, then `herdr pane process-info --pane P` for each): close it
  only when every one is a bare `zsh`.

1. **✓ ≠ done.** Read the pane before offering an agent. Its last message decides.
2. **Removing a worktree with `git` alone leaves a herdr space on a missing folder.** `fleet clean`
   goes through `herdr worktree remove` for exactly this reason, and tier A closes any orphans
   left over from earlier.
3. **Sync never merges, rebases, or resets.** It only fast-forwards. `SKIP diverged ↑N` means someone
   has local commits there, which is a human's call.
4. **Other owners.** On m5, `arra-oracle-v4` and `odoo-yd` belong to other agents' work. Use
   `--skip arra-oracle-v4,odoo-yd` unless the user names them.
5. **Idle shells on main checkouts** (a bare `main` row) are not worktrees. `clean` never
   removes a main checkout. Closing those spaces is a separate `herdr workspace close <id>`
   the user must ask for.
