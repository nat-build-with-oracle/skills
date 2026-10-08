---
name: herdr-send
description: Hand a task to ANOTHER oracle and pick the engine that does it — opens a GitHub issue in the target oracle's repo carrying the full brief, cuts a worktree under that repo's wt/ (the /herdr-wt flow), starts claude, codex or omx in it, and briefs the agent from the issue. Optionally makes "incubate org/repo" the agent's first step. Use when the user says "send to neo", "hand this to <oracle>", "have <oracle> do X", "neo incubate this repo", "use codex/omx for it", or /herdr-send. Do NOT use for work in the current repo (use /herdr-wt), to open another oracle's own repo as a space with no task (use /herdr-bring), or to message an agent that already exists (use /herdr-hey).
argument-hint: "<oracle> <slug> --task \"...\" [--engine claude|codex|omx] [--incubate org/repo | --incubate-here] [--dry-run]"
---

# /herdr-send — give another oracle a task, in its own worktree

`/herdr-wt` cuts a worktree in the **current** repo. `/herdr-send` does the same five steps
in **someone else's** repo, and lets you choose who runs the work:

1. issue in the target oracle's repo (the brief, durable and linkable)
2. worktree `<target>/wt/<slug>-<owner>-issue<N>-<date>`, locked, `maw token use`, lab folder
3. workspace recorded on the issue as a comment
4. agent started: **claude**, **codex** or **omx**
5. agent briefed with a short prompt that points at the issue

Everything is one script: `~/.claude/skills/herdr-send/herdr-send.sh`.

## Run it — always dry-run first

```bash
S=~/.claude/skills/herdr-send/herdr-send.sh

# 1. show the plan and the issue body; creates nothing
$S neo incubate-pulse --task "Study the Pulse SDK and write a one-page map" \
   --incubate-here --engine omx --dry-run

# 2. show that plan to the user; when they agree, the same line without --dry-run
$S neo incubate-pulse --task "Study the Pulse SDK and write a one-page map" \
   --incubate-here --engine omx
```

The real run opens an issue in another oracle's repo and starts an agent there, so it is
outward-facing. Show the dry-run and get a yes first, unless the user already said
exactly what to send, to whom and with which engine.

| argument | meaning |
|---|---|
| `<oracle>` | as `maw locate` knows it: `neo`, `homekeeper`. An ambiguous name (`fireman`) exits 2 with the choices; re-run with `<org>/fireman-oracle` |
| `<slug>` | kebab-case name of the work; branch prefix and agent name |
| `--task "..."` / `--task-file F` | the goal. First line becomes the issue title. Write it for someone who has never seen this conversation |
| `--engine` | `claude` (default), `codex`, `omx` |
| `--incubate org/repo` | the agent's first step is to clone that repo and work in it |
| `--incubate-here` | same, with the current repo (taken from the `origin` URL) |
| `--base REF` | branch point in the target repo (default `HEAD`) |

## Engines

| engine | started with | notes |
|---|---|---|
| `claude` | `claude` via `pane run` | gets the worktree's token through direnv; the issue says `/incubate` |
| `codex` | `codex --dangerously-bypass-approvals-and-sandbox` | **no approvals, no sandbox**. Codex has no Claude skills, so the issue spells out the `ghq get` + `ψ/incubate` symlink by hand |
| `omx` | `OMX_AUTO_UPDATE=0 omx --direct --madmax` | same bypass; flags explained in `/herdr-buddy`. Stops at the **hooks trust gate** on a new state dir: the script exits 2 and the human answers it, never the agent |

codex and omx run with approvals bypassed in a fresh worktree, which is exactly the place
`/herdr-buddy` allows it: never the main checkout.

## Exit codes

| code | meaning | what to do |
|---|---|---|
| 0 | issue, worktree, agent and brief all done | report the issue URL, space and pane |
| 1 | real error | read the message; say which steps already happened (issue URL is printed early) |
| 2 | a human decides: ambiguous oracle, worktree name already exists, omx trust gate | ask with `AskUserQuestion`, then re-run |
| 64 | bad arguments | fix the call |

## Traps it already handles (measured, see the linked skills)

- `maw locate` returns the path as `repoPath` **or** `local_path`, and an ambiguous name
  prints text on stderr instead of JSON. Both handled (2026-09-29).
- `gh repo view` follows renames (`<org>/pulse` → `pulse-oracle`), so `--incubate-here`
  reads the `origin` URL instead; otherwise ghq clones a second copy.
- A fresh worktree's shell starts before `maw token use` trusts it, so a throwaway command
  runs first to make direnv load (`/herdr-wt`, "pane run is not enough").
- Agent names cap at 32 characters; the script falls back to the slug.
- The brief goes by **pane id**, which is exact. A name can prefix-match another agent.
- **codex / omx never read `idle`** (2026-10-03): herdr reports them `working` while they wait at
  their prompt, so the script waits for the prompt itself (`Ask Codex to do anything`) or the
  hooks trust gate, with `wait-output --regex … --source visible`. Never `--source recent` on an
  agent pane: a history read makes the agent redraw its whole screen.
- **Agent names are lowercase only** (`invalid_agent_name` otherwise); the script lowercases.
- A launch waited on in the agent's own turn blocks it: fire, and let the worker report back with
  `herdr agent prompt <your pane> "LANE …: <PR url | BLOCKED: …>"` (see the brief template).
- Issues only open where we have write access; never on a third-party repo.

## After it runs

- Watch: `herdr pane read <pane> --source recent-unwrapped --lines 24 | tail -18`
- Talk to it later: `/herdr-hey`, by pane id or its name.
- Anything that changes the task goes on the issue as a comment first, then one line in
  the pane pointing at it. The pane is never the only copy.
- Cleanup is the `/herdr-wt` cleanup (unlock, `herdr worktree remove`, prune).

## Related

- `/herdr-wt` — the same flow in the current repo; naming and lock rules live there
- `/herdr-incubate` — a worktree of the CURRENT repo for another oracle's topic
- `/herdr-buddy` — omx/codex beside you instead of in another oracle's repo
- `/herdr-hey` — message an agent that already exists
