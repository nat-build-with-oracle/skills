# Oracle skills

Skills for Claude Code built around [herdr](https://github.com/herdrdev/herdr) —
parallel worktree spaces, sessions you can address by name, and PRs that say who
to ask when they are wrong.

Each skill carries the traps that shaped it. The failure modes are the point: a
skill that only describes the happy path teaches nothing the model could not
guess.

## Install

One skill:

```sh
npx skills@latest add nat-build-with-oracle/skills --skill=herdr-pr
```

Everything:

```sh
npx skills@latest add nat-build-with-oracle/skills
```

Or as a Claude Code plugin:

```
/plugin marketplace add nat-build-with-oracle/skills
/plugin install oracle-herdr-skills@build-with-oracle
```

Run `/setup-herdr-skills` once per machine afterwards — it checks that herdr is
reachable, names this pane's agent, and records the repo conventions the rest
assume.

## The skills

| Skill | What it does |
|---|---|
| `setup-herdr-skills` | Preflight: herdr reachable, agent named, conventions recorded |

**Spaces and worktrees**

| Skill | What it does |
|---|---|
| `herdr-wt` | One worktree + one space per unit of work, named so you can find it a week later; opens the issue first |
| `herdr-bring` | Land an existing repo or handle into a herdr space |
| `herdr-idea` | Spin an idea into its own throwaway space without touching the main tree |
| `herdr-incubate` | Work someone else's repo from your oracle, with a breadcrumb linking the two |
| `herdr-issue` | Task to a GitHub issue in the right repo first, then a worktree and a briefed agent *(needs fleet)* |
| `herdr-ticket` | Turn a session's findings into tickets that survive the session |
| `herdr-team` | Bring up a team charter as agents in one space |

**Talking to the agent next door**

| Skill | What it does |
|---|---|
| `herdr-buddy` | Bring up a second agent beside you in the same space |
| `herdr-neighbors` | Survey every pane around you before touching any |
| `herdr-peek` | Look at what the neighbouring agent is doing without interrupting it |
| `herdr-hey` | Send the neighbour a message and read its answer |
| `herdr-send` | Hand a task to another oracle and pick the engine that does it |
| `herdr-handover` | Hand ownership of a live surface to a peer agent |
| `herdr-pane-run` | Run a long command in a pane so you watch it live and the agent still gets the exit code |

**Finishing and tidying**

| Skill | What it does |
|---|---|
| `herdr-pr` | Sign a PR with which oracle, which model, which commit, and an address that answers back |
| `herdr-done` | Decide whether a session can be closed without losing work |
| `herdr-dissolve` | Wind a worktree down: commit, push, signed PR, report to the parent, remove *(needs fleet)* |
| `herdr-clean-up-sync` | Tidy the sidebar on one or more machines and fast-forward checkouts that are only behind *(needs fleet)* |
| `herdr-sleep` | Put spaces to sleep and wake them exactly where they were *(needs fleet)* |
| `herdr-vacation` | Park idle agents before you go away, keep everything *(needs fleet)* |

### fleet

The five skills marked *(needs fleet)* drive the `fleet` CLI from
[nat-build-with-oracle/herdr-fleet](https://github.com/nat-build-with-oracle/herdr-fleet)
(MIT). Install it once per machine, see that repo's README; the other skills
do not need it.

## Requirements

- [herdr](https://github.com/herdrdev/herdr) installed, with its server running
- `git` ≥ 2.36 (`worktree list --porcelain -z`)
- [`ghq`](https://github.com/x-motemen/ghq) for repo resolution
- `gh` for the PR and ticket skills
- `bun` and the `fleet` CLI, for the five skills marked *(needs fleet)*
- `yq` if you want to parse `/herdr-pr` signature blocks mechanically

## Conventions

Paths in these skills are written as `$(ghq root)/github.com/<org>/<repo>` and
oracle repos as `<oracle>-oracle`. Substitute your own; nothing here hardcodes a
particular machine or organization.

`/herdr-pr` decides how much local detail to print by reading the target repo's
visibility. A public repo gets a block with the agent's own storage — transcript,
memory directory, herdr socket — omitted. See that skill for the full rule.

## License

MIT
