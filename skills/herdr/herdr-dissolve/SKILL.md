---
name: herdr-dissolve
description: The reverse of /herdr-wt — wind a worktree down properly. Each worktree's own agent commits its work, pushes, opens a signed PR and reports to its PARENT (the repo's main-checkout agent), then the worktree is removed, its agent quit (transcript kept) and its herdr space closed. Run it from a lead pane over one or many worktrees, or from inside a worktree to dissolve yourself. Use when the user says "dissolve", "herdr dissolve", "wind down this worktree", "finish and close", "commit push pr and close", "done with this wt", or /herdr-dissolve. Do NOT use to clean up many already-finished worktrees in one sweep (use /herdr-clean-up-sync), to create a worktree (/herdr-wt), or when there is no agent in the worktree (then it is just `fleet clean --pick`).
argument-hint: "[worktree-name|pane ...] | self"
---

# /herdr-dissolve: the reverse of /herdr-wt

> **Needs `fleet`.** This skill drives the `fleet` CLI from
> [nat-build-with-oracle/herdr-fleet](https://github.com/nat-build-with-oracle/herdr-fleet).
> Install: `git clone https://github.com/nat-build-with-oracle/herdr-fleet.git && cd herdr-fleet && mkdir -p ~/.local/share ~/.local/bin && ln -sfn "$PWD" ~/.local/share/herdr-fleet && ln -sfn ~/.local/share/herdr-fleet/fleet.ts ~/.local/bin/fleet && bun install`
> then check with `fleet help | head -3`.

`/herdr-wt` makes a branch, a locked worktree, a space and an agent. This undoes it in
the right order. **The agent that did the work saves it and reports first.** Only then is
the worktree dissolved. Nothing it knows is lost: the work lands in a PR, the summary
reaches the parent, and the transcript stays in `~/.claude/projects`.

```
 worktree agent                 parent (main checkout agent)          lead / fleet
 ──────────────                 ────────────────────────────          ────────────
 1 commit (no .envrc/.codex)
 2 push branch
 3 PR, signed /herdr-pr   ──►   4 gets: PR url + what was done +
                                  what is left (fleet send)
 5 says DISSOLVE-READY    ────────────────────────────────────────►  6 fleet clean --pick <wt>
                                                                        quits agent, removes
                                                                        worktree + space
```

## Who is the parent

The parent is the agent in the repo's **main checkout**: the pane whose cwd is the
repo root, where `/herdr-wt` was run.

```bash
repo=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir | xargs dirname)
herdr pane list | jq -r --arg r "$repo" '.result.panes[]
  | select((.foreground_cwd // .cwd) == $r and .agent) | .pane_id' | head -1
```

If no agent is running there, the parent report becomes a file in main's vault,
`$repo/ψ/inbox/handoff/<date>_dissolve_<wt>.md`, and the lead reads it out to the human.

## Lead mode: `/herdr-dissolve <wt> [<wt> ...]`

For each worktree:

1. **Check.** Run `fleet audit --pick <wt> --idle-agents --min-age 0 --json`.
   - Find its agent pane.
   - If the agent is **working or blocked, stop** for that row: never dissolve mid-turn.
   - If its last message is a question to the human, show the question and ask before going on.
2. **Brief the agent** with `fleet send <pane> "<brief>"`, never `herdr agent prompt`. The brief asks for:
   - Commit everything that is work on this worktree's branch. Never `.envrc`, `.codex/`, `.env*`, shell snapshots or credentials. Hooks off: `git -c core.hooksPath=/dev/null commit`.
   - Push the branch, and open a PR signed with `/herdr-pr`. If nothing changed, say so and skip the PR.
   - Tell the parent with `fleet send <parent-pane> "…"`, in at most 6 lines:
     - PR url
     - what was done
     - what is verified
     - what is left open
     - anything the parent must pick up
   - Finish with the single line `DISSOLVE-READY <pr-url|no-changes>`.
3. **Wait** with `fleet watch <pane>`. When it goes idle, read it with `fleet tail <pane>` and confirm the `DISSOLVE-READY` line.
4. **Dissolve** with `fleet clean --pick <wt> --tier B,C,D --go`. This:
   - re-checks that the worktree is clean and pushed
   - quits the agent with ctrl-c (the transcript stays)
   - removes the worktree and closes the space through `herdr worktree remove`
   - refuses if anything real is still uncommitted, or if gitignored data is over 50 MB

   The **branch stays** until its PR merges.
5. **Report** one row per worktree: PR, the parent's acknowledgement, removed yes/no, and why not.

Do several worktrees in parallel: brief them all, then watch them all. If one fails,
don't stop the others.

## Self mode: `/herdr-dissolve self` (run inside the worktree)

Do steps 2a–2c yourself: commit, push, signed PR, report to the parent. You cannot remove
the worktree you're running in, so hand that step off:

```bash
fleet send <parent-pane> "DISSOLVE-READY <pr-url> — please: fleet clean --pick $(basename "$PWD") --go"
```

Or ask the lead or the human to run it. Then stop working, since your worktree is about to go away.

## Guards

- **Never dissolve a working agent.** A ✓ means it finished its turn, not its task. Read its last message.
- **Unsaved data blocks the removal.** `fleet clean` keeps a worktree holding more than 50 MB of gitignored data that can't be rebuilt. Move that data (or check with relic that it's superseded) first. Don't bypass the check.
- **Public repo:** before the PR, list what is being committed. Nothing private, and no tool homes.
- **Nothing merges here.** The PR waits for a human. Dissolving the worktree doesn't merge anything or delete the branch.

## Related

- `/herdr-wt`: creates what this dissolves
- `/herdr-issue`: issue first, then a worktree; dissolve when the PR is up
- `/herdr-clean-up-sync`: the sweep for many worktrees whose agents already finished
- `/herdr-pr`: the signature on the PR
