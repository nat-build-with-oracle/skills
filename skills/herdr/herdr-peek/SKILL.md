---
name: herdr-peek
description: Look at what the agent in the neighbouring herdr pane is doing, without interrupting it. Resolves your own pane, finds the buddy beside you, reports whether it holds an agent or a bare shell, and reads its recent scrollback. Use when the user says "peek", "what is my buddy doing", "what's codex doing", "check the pane next to you", "is it still working". Read-only — sends no keystrokes. To TALK to the buddy use /herdr-hey; to CREATE one use /herdr-buddy.
argument-hint: "[left|right|up|down]"
---

# /herdr-peek — look without touching

Read-only. Sends nothing to the other pane — no text, no keys, no prompt. Safe against
a buddy mid-task, which is the whole point: you want to know if it is stuck without
being the thing that interrupts it.

To send something, that is [[herdr-hey]]. To create the buddy, [[herdr-buddy]].

## Run it

```bash
DIR=right      # left | right | up | down

# $HERDR_PANE_ID is YOUR pane, set in the pane's own environment. Prefer it over
# --current, which resolves through focus -- see the trap below.
me="${HERDR_PANE_ID:-$(herdr pane current | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane']['pane_id'])")}"

# .get(), NOT ['neighbor_pane_id'] -- the key is ABSENT when there is no neighbour,
# so subscripting raises KeyError instead of reporting "none".
buddy=$(herdr pane neighbor --pane "$me" --direction "$DIR" 2>/dev/null \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['neighbor'].get('neighbor_pane_id',''))")

[ -n "$buddy" ] || { echo "no pane to the $DIR of $me"; exit 1; }

# Occupied by an agent, or a bare shell? This decides what you may do NEXT.
herdr agent list | python3 -c "
import json,sys
b=sys.argv[1]
for a in json.load(sys.stdin)['result']['agents']:
    if a['pane_id']==b:
        print(f\"{b}: {a['agent']} '{a.get('name') or '(unnamed)'}' [{a['agent_status']}] cwd={a.get('cwd','')}\")
        break
else:
    print(f'{b}: bare shell (no agent)')
" "$buddy"

herdr pane read "$buddy" --source recent-unwrapped --lines 24 | tail -18
```

## Always report occupancy, not just the text

The occupancy line is the load-bearing half, and it is the reason this skill resolves
the agent list at all rather than going straight to `pane read`.

A pane holding an agent and a pane holding a bare shell look identical in scrollback —
both are text. They are not interchangeable targets:

| buddy is | send text with | what happens if you get it wrong |
|---|---|---|
| an agent | `herdr agent prompt <name-or-pane>` | a shell command lands in its PROMPT and it may act on it |
| a bare shell | `herdr pane run <pane> '<cmd>'` | a prompt lands in a shell and executes as a command |

Measured 2026-09-19: a `wrangler tail` command was sent to a pane believed to be a free
shell. It held a live Claude agent, the command arrived as a user turn, and the agent
went `working` on it. `herdr pane list` had been checked — but only the `cwd` was read,
and cwd does not say whether anyone is home. **`herdr agent list` is the check that
matters.**

## `tail`, never `head`

The interesting state is at the END of the scrollback — the current prompt, the last
result, the status line. `--lines 24 | tail -18` keeps the tail and drops the wrapped
fragment at the top.

`--source recent-unwrapped` is the right source for reading back: `visible` gives only
the current viewport, and plain `recent` re-wraps long lines at the pane width, which
mangles paths and JSON.

## Trap: `pane_id` is the SOURCE, `neighbor_pane_id` is the answer

`herdr pane neighbor` returns BOTH, and the obvious-looking key is the wrong one:

```json
{ "direction": "right",
  "pane_id": "<pane>",            // <- YOU. the pane you asked FROM
  "neighbor_pane_id": "<pane>",   // <- the buddy. what you want
  "layout": { … } }
```

A `d.get('pane_id')` fallback chain silently returns your own pane, and then you peek
at yourself and see your own output looking back. That is confusing rather than
failing, which makes it expensive — verified by doing exactly this.

`layout.panes[]` also lists every pane in the tab with a `focused` flag. Picking "the
one that is not focused" works only in a two-pane tab and breaks silently in three.
Use `neighbor_pane_id`.

## No neighbour in that direction — and it is TRANSIENT

When there is no pane that way, `neighbor_pane_id` is **absent from the response
entirely**, leaving only `direction`, `layout`, `pane_id`:

```python
n['neighbor_pane_id']            # KeyError -- crashes instead of reporting
n.get('neighbor_pane_id', '')    # '' -- an answer you can test
```

Verified by writing the crashing form first and running it.

It is an answer, not an error. Do NOT fall back to "pick the other pane from
`herdr pane list`" — a pane existing in the tab does not make it a directional
neighbour, and a guessed pane is how you end up reading, or writing to, the wrong
session.

**Expect it to flicker.** Measured 2026-09-19: the same call returned `<pane>`, then
nothing, then `<pane>` again within a minute, while the buddy pane existed the whole
time — the layout was mid-change as the human moved focus between panes. A single
empty read means "not right now", not "there is no buddy". Re-run before concluding.

## Trap: `--current` means different things to different subcommands

**It is not uniform across the CLI**, which is what makes this expensive. Measured on
herdr **0.9.1**:

| call | resolves to |
|---|---|
| `herdr pane current` | **your own pane** — does not move with focus |
| `herdr pane neighbor --current` | the **focused** pane — moves when the human clicks |

So `pane current` is safe and `pane neighbor --current` is not, and nothing in the flag
name distinguishes them. The moment the human clicks another pane, `neighbor --current`
quietly answers a different question — "what is to the right of the pane the human is
looking at" instead of "what is to the right of me" — and returns a real pane id, so it
looks like it worked.

`$HERDR_PANE_ID` is set in your pane's own environment and never moves. Pass it:

```bash
herdr pane neighbor --pane "$HERDR_PANE_ID" --direction right
```

Both forms agree while you are the focused pane, which is exactly why this needs writing
down: it agrees until the human clicks, and then it does not.

> The per-subcommand split was found by **glyph-codex** (Codex, `gpt-6-astra`) on
> 2026-09-19, running the two calls side by side rather than taking the general claim on
> trust. This skill originally said "`--current` follows the focus" flat out — true of
> `pane neighbor`, false of `pane current`, and the flat version would have sent someone
> chasing a bug in the wrong command.

## Related

[[herdr-hey]] talks to the buddy. [[herdr-buddy]] creates one. [[herdr-pane-run]] runs
a long command in a pane and has it report back. [[herdr]] is the CLI reference.
