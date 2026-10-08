---
name: herdr-team
description: Bring up a team charter (ψ/teams/*.yaml) as agents in ONE herdr space — the worktree's own space, Fibonacci layout (first member on the left and biggest, the rest stacked on the right), each member started with its engine (omp, omx, codex or claude), named, and briefed with its charter prompt. Use when the user says "team of omp/omp/omx", "spawn the team in one worktree", "3 panes fibonacci", "bring up the charter in herdr", or /herdr-team. Do NOT use for tmux-based teams (use /team-up), for one buddy beside you (use /herdr-buddy), or to create the worktree itself (use /herdr-wt first).
argument-hint: "<worktree> <charter.yaml> [--dry-run] [--no-brief]"
---

# /herdr-team — one worktree, one space, a whole team

`/team-up` does this for tmux, with one worktree window per member. `/herdr-team` puts the
whole team in **one** herdr space on **one** worktree, laid out so the lead can watch all of
them at once:

```
┌──────────────────┬───────────┐
│                  │ member 2  │
│    member 1      │  (top)    │
│    (61.8%)       ├───────────┤
│                  │ member 3  │
│                  │ (bottom)  │
└──────────────────┴───────────┘
```

More members keep spiralling: each new split takes the remaining corner (right, down,
right…), and the last split halves what is left.

## Flow

1. `/herdr-wt <slug>` (or `--repo`) → worktree + its own space, issue first.
2. Write the charter at `ψ/teams/<team>.yaml` in that worktree (schema below).
3. Dry-run, then the real run. The real run blocks while agents start (up to ~2 min each),
   so fire it through `/herdr-pane-run`, not a blocking Bash call.

```bash
T=~/.claude/skills/herdr-team/herdr-team.sh
$T <worktree> ψ/teams/<team>.yaml --dry-run      # table of members, engines, positions
$T <worktree> ψ/teams/<team>.yaml                # split, start, name, brief
```

## Charter schema (the "full" schema, same as ψ/teams elsewhere)

```yaml
name: flood-data-team
issue: https://github.com/<org>/<repo>/issues/<N>
engines:                       # optional; overrides the defaults below
  omp: "omp --approval-mode=yolo"
  omx: "OMX_AUTO_UPDATE=0 omx --direct --madmax"
members:
  - role: lead                 # skipped: the lead is the session running this
    name: pulse
    engine: claude
  - role: worker               # every non-lead member gets a pane, in file order
    name: omp-rain             # becomes the herdr agent name (≤32, lowercase)
    engine: omp
    cwd: ψ/incubate/<repo>     # relative to the worktree; optional
    prompt: >-                 # sent as ONE line once the agent settles
      You are omp-rain ... Read issue #N first ...
```

Default engine commands: `omp --approval-mode=yolo`, `OMX_AUTO_UPDATE=0 omx --direct
--madmax`, `codex --dangerously-bypass-approvals-and-sandbox`, `claude`. All but claude
bypass approvals, which is why the team must live in a worktree and never the main checkout.

## What it guards

- Refuses a space that already has more than one pane, or whose root pane already holds
  an agent: it lays out a **fresh** space only, so it never types into someone's session.
- A throwaway command runs in every pane before the engine starts, so direnv loads the
  worktree's `.envrc` (`/herdr-wt`, "pane run is not enough").
- **Trust gates**: omx "Hooks need review" and codex "Trust this folder?" (first run in a new repo). Detected, the brief is withheld, and the human answers it.
  Never the script.
- **omp is not always detected as a herdr agent.** In that case "ready" means the screen
  stopped changing, and the brief is typed with `pane run` instead of `agent prompt`.
  Check the omp panes once after the run.

## After

- Chase through the issue: each member posts progress there. The pane is never the only copy.
- Peek without interrupting: `/herdr-peek`. Talk to one: `/herdr-hey`, by pane id.
- Teardown: close the agents first, then the `/herdr-wt` cleanup.

## Related

- `/herdr-wt` — the worktree and issue this runs in
- `/team-up` — the tmux version, one window per member
- `/herdr-buddy` — a single bypass buddy beside you
- `/herdr-send` — hand a task to another oracle's repo
