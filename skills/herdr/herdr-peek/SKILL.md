---
name: herdr-peek
description: See what every herdr agent is doing right now, and what any one of them last printed — the herdr counterpart to `maw peek`. Use when the user says "peek", "herdr peek", "what are the agents doing", "is X still working", "show me what X printed", or when a background agent has gone quiet. Do NOT use to send an agent a message (use `herdr agent prompt`), to jump a terminal to it (`herdr agent focus`), or to audit whether a session can be closed (use /herdr-done).
---

# /herdr-peek — what is everyone doing?

`maw peek` reads a pane on the maw side. This reads the herdr side, by agent
name, without moving anyone's window.

## Run it

```bash
# every agent, one line each
~/.claude/skills/herdr-peek/herdr-peek.sh

# tail one agent's terminal
~/.claude/skills/herdr-peek/herdr-peek.sh glyph-oracle
~/.claude/skills/herdr-peek/herdr-peek.sh glyph-oracle --lines 60

# a pane id works too, when an agent has no name yet
~/.claude/skills/herdr-peek/herdr-peek.sh w2:p1

# everything, with each agent's tail underneath
~/.claude/skills/herdr-peek/herdr-peek.sh --all --lines 10
```

Roster output is one line per agent plus its cwd:

```
  ◐ mycelium-reincarnate   working  claude    do ! ls changes
     /opt/Code/github.com/…/wt/mycelium-reincarnate-17sep-thu2026
* ○ glyph-oracle           idle     claude    Sales order mock data list
     /opt/Code/github.com/dryoungdo-wellness-clinic/glyph-oracle
```

`*` marks the focused pane. State is carried by glyph — `◐` working, `○` idle,
`◔` waiting, `·` unknown — never by colour alone, because this gets read over
SSH and through pipes.

## Traps

1. **Peeking must not focus.** `herdr agent focus` moves the human's window; on a
   machine where someone is typing, a "quick look" that steals the pane is worse
   than no look at all. This skill only ever calls `herdr agent list` and
   `herdr agent read`.

2. **Parse with `\x1f`, not tab** — an agent with no name is the *common* case
   here, and a whitespace IFS silently shifts every later field one column left.
   The roster then prints a status where the runtime belongs and looks fine.

3. **Two calls, two moments.** The roster and a tail are separate requests, and a
   live fleet changes between them. An agent listed as `idle` may be working by
   the time you read its output. Re-run rather than reasoning from a stale line.

4. **No output is not "dead".** `herdr agent read` returns nothing for an agent
   that has printed nothing since its terminal was created, and for a stale name.
   Check the roster before concluding anything from an empty tail.

5. **`--all` scales with the fleet.** Ten agents at `--lines 40` is four hundred
   lines into your context. Default is 20 lines, and naming one agent is almost
   always what you actually wanted.

## Don't use it for

Sending work (`herdr agent prompt <name> "…"`), jumping a terminal
(`herdr agent focus <name>`), or deciding whether a session can be closed
(`/herdr-done`). This only looks.
