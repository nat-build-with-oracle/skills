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
| `herdr-wt` | One worktree + one space per unit of work, named so you can find it a week later |
| `herdr-bring` | Land an existing repo or handle into a herdr space |
| `herdr-idea` | Spin an idea into its own throwaway space without touching the main tree |
| `herdr-incubate` | Work someone else's repo from your oracle, with a breadcrumb linking the two |
| `herdr-pr` | Sign a PR with which oracle, which model, which commit, and an address that answers back |
| `herdr-ticket` | Turn a session's findings into tickets that survive the session |
| `herdr-buddy` | Bring up a second agent beside you in the same space |
| `herdr-peek` | See what every agent is doing, and what any one of them last printed |
| `herdr-done` | Decide whether a session is safe to close, and what hand-off is still owed |

## Requirements

- [herdr](https://github.com/herdrdev/herdr) installed, with its server running
- `git` ≥ 2.36 (`worktree list --porcelain -z`)
- [`ghq`](https://github.com/x-motemen/ghq) for repo resolution
- `gh` for the PR and ticket skills
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
