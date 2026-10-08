---
name: setup-herdr-skills
description: "Check that herdr is installed and reachable, name this pane's agent, and record the repo conventions the other herdr skills assume (ghq root, oracle naming, worktree root). Run once per machine before first use of the other herdr skills."
disable-model-invocation: true
---

# Set up the herdr skills

The other skills in this pack assume three things exist. This checks each one and
fixes what it can, rather than failing halfway through a worktree creation.

## 1. herdr is installed and its server is up

```bash
herdr --version || echo "not installed"
herdr agent list >/dev/null 2>&1 && echo "server reachable" || echo "server not running"
```

If `herdr` is missing, stop and install it first — every skill here shells out to
it. If the binary exists but `agent list` fails, the server is not running; start
it before continuing.

## 2. This pane's agent has a name

The name is the address. An unnamed agent can only be reached by pane id, and
pane ids are reassigned when the herdr server restarts — so a signature or a
handoff pointing at one silently starts addressing a different agent.

```bash
herdr agent get "$HERDR_PANE_ID" | grep -q '"name"' \
  && echo "already named" \
  || herdr agent rename "$HERDR_PANE_ID" <name>
```

Pick a name that survives the work: the oracle plus what this session is for
(`neo-digger`), not the ticket number.

## 3. The repo conventions these skills assume

Confirm each with the user, then write the answers into the repo's `CLAUDE.md`
(or `AGENTS.md`) so every future session inherits them:

| Convention | Default | Used by |
|---|---|---|
| ghq root | `$(ghq root)` | every skill that resolves a repo path |
| Oracle naming | `<name>-oracle` repo → `<name>` in space names | `/herdr-wt`, `/herdr-incubate` |
| Worktree root | `<repo>/wt/<slug>` | `/herdr-wt`, `/herdr-bring` |
| Incubation root | `ψ/incubate/<owner>/<repo>/origin` | `/herdr-incubate`, `/herdr-pr` |
| Space naming | `<oracle>-<slug>-<DDmmm>-<dow><year>` | `/herdr-wt`, `/herdr-idea` |

Do not invent these silently. If a repo already has its own worktree or naming
convention, record **that** — the skills read the convention, they do not enforce
this particular one.

## 4. Verify

```bash
herdr agent get "$HERDR_PANE_ID"   # named, with a session id
ghq root                           # resolves
git rev-parse --show-toplevel      # you are in a repo
```

All three answering means `/herdr-wt`, `/herdr-pr`, `/herdr-bring`,
`/herdr-incubate`, `/herdr-idea`, `/herdr-ticket` and `/herdr-buddy` will run
without their setup preconditions failing mid-flight.

## 5. fleet (only for five skills)

`/herdr-clean-up-sync`, `/herdr-dissolve`, `/herdr-issue`, `/herdr-sleep` and
`/herdr-vacation` call the `fleet` CLI. The other skills do not. Check, and
install from [herdr-fleet](https://github.com/nat-build-with-oracle/herdr-fleet)
if it is missing:

```bash
command -v fleet >/dev/null && fleet help | head -3 || {
  git clone https://github.com/nat-build-with-oracle/herdr-fleet.git "$(ghq root)/github.com/nat-build-with-oracle/herdr-fleet"
  cd "$(ghq root)/github.com/nat-build-with-oracle/herdr-fleet"
  mkdir -p ~/.local/share ~/.local/bin
  ln -sfn "$PWD" ~/.local/share/herdr-fleet
  ln -sfn ~/.local/share/herdr-fleet/fleet.ts ~/.local/bin/fleet
  bun install
}
```
