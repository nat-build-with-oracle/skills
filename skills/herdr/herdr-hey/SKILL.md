---
name: herdr-hey
description: Send a message to the agent in the neighbouring herdr pane and read what it says back. Resolves the buddy pane, checks whether it holds an agent or a bare shell, and routes the message the right way for each. Use when the user says "hey", "ask my buddy", "tell codex", "ask the pane next to you", "message the buddy". To LOOK without interrupting use /herdr-peek; to CREATE a buddy use /herdr-buddy.
argument-hint: "<message> [left|right|up|down]"
---

# /herdr-hey — talk to the pane beside you

Writes to another agent's session. Unlike [[herdr-peek]], this interrupts — the message
lands as a user turn and the buddy will act on it. Say something worth its attention.

## Resolve the target BEFORE sending anything

```bash
DIR=right; MSG="your message here"

# --pane "$HERDR_PANE_ID", not --current: --current follows the FOCUS, so the moment
# the human clicks another pane it resolves somewhere else -- and messaging the wrong
# session is worse than peeking at it. .get() because the key is ABSENT when there is
# no neighbour, and subscripting would raise KeyError instead of reporting "none".
me="${HERDR_PANE_ID:-$(herdr pane current | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane']['pane_id'])")}"
buddy=$(herdr pane neighbor --pane "$me" --direction "$DIR" 2>/dev/null \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['neighbor'].get('neighbor_pane_id',''))")
[ -n "$buddy" ] || { echo "no pane to the $DIR of $me — re-run, the layout flickers mid-focus-change"; exit 1; }

kind=$(herdr agent list | python3 -c "
import json,sys
b=sys.argv[1]
for a in json.load(sys.stdin)['result']['agents']:
    if a['pane_id']==b:
        print(a.get('name') or b); break
else: print('SHELL')
" "$buddy")
```

Then route on what it actually is — these are not interchangeable:

```bash
if [ "$kind" = "SHELL" ]; then
  echo "REFUSING: $buddy is a bare shell, not an agent."
  echo "A message typed into a shell runs as a command. Use /herdr-pane-run instead."
  exit 1
fi

herdr agent prompt "$kind" "$MSG"
```

## Why the shell check is a refusal, not a fallback

Sending prose to a bare shell executes it as a command. Sending a command to an agent
puts it in the agent's prompt, where it may be acted on as an instruction.

Measured 2026-09-19: `herdr pane run <pane> 'npx wrangler tail …'` was aimed at a pane
believed free. It held a live Claude agent; the command arrived as a user turn and the
agent went `working` on it. The mistake was checking `herdr pane list` and reading only
`cwd` — **cwd does not say whether anyone is home. `herdr agent list` does.**

So this skill refuses rather than guessing. The recovery when it happens anyway is a
short correcting message — *"misrouted, please ignore, no action needed"* — not a retry
and not silence.

## Address by NAME when the agent has one

`herdr agent prompt` takes a name or a pane id. Prefer the name — but **neither is
durable**, and it is worth being exact about why:

| target | lifetime | failure mode |
|---|---|---|
| agent name | **only while that agent lives** — herdr's own docs: *"A name follows the current pane occupant and is cleared when that agent exits, is released, or is replaced"* | goes absent — `agent_not_found`, a loud failure |
| pane id | reassigned when herdr restarts | silently points at **someone else** — a quiet failure |

So the name is not "persistent"; it is **unambiguous while live**, and it fails loudly
when it stops being valid. That is the whole advantage. A stale pane id delivers your
message to whoever inherited the id, and nothing errors.

Do not tell anyone a name will survive a restart. Re-resolve before messaging after any
gap:

```bash
herdr agent list | rg '<name>'     # gone? re-resolve by pane, then rename again
```

> This table originally claimed names were "stable, re-claimable after a herdr restart".
> **glyph-codex** (Codex, `gpt-6-astra`, 2026-09-19) flagged it as untested and pointed at
> the installed herdr docs, which say the opposite. Corrected. They were careful to say
> they had not tested restart persistence rather than asserting either way — which is
> what made the correction easy to check.

An unnamed agent leaves only the pane id. Name it first if you will message it again:

```bash
herdr agent rename "$buddy" <owner>-<slug>     # names cap at 32 chars
```

## Reading the reply

`herdr agent prompt` returns as soon as the message is delivered — **not** when the
buddy has answered. It does not carry a reply.

```bash
herdr agent read "$kind"                                  # what it printed back
herdr pane read "$buddy" --source recent-unwrapped --lines 24 | tail -18
```

Do not `sleep` waiting for it. Fire the message, keep working, and read later — the
same discipline as [[herdr-pane-run]]. If a real wait is genuinely needed it belongs to
the pane (`herdr pane wait-output --match <str>`), never to a `sleep` in your own turn.

## Write it like a message to a colleague

The buddy is another agent with its own context, and it cannot see yours. What lands
well, learned from a day of cross-agent exchanges that each caught a real error:

- **Say who you are and which session.** `my-agent (<pane>), session <session>`.
- **Lead with the measurement, not the conclusion.** Paste the command and its output.
  A peer can check a measurement; it cannot check an assertion.
- **Separate what you verified from what you inferred.** The exchanges that worked were
  the ones where both sides could tell which was which.
- **When you are wrong, concede in one line and move on.** No re-litigating.
- **Say what is theirs to decide.** Do not act on another agent's surface because you
  happened to notice it.

Write it in prose, not caveman — it is persisted output going to someone else.

## Trap: `--current` is not uniform across subcommands

Measured on herdr **0.9.1** by [[herdr-peek]]'s co-author glyph-codex:

| call | resolves to |
|---|---|
| `herdr pane current` | **your own pane** — stable |
| `herdr pane neighbor --current` | the **focused** pane — moves when the human clicks |

Here that difference is not cosmetic: `neighbor --current` returns a real pane id after
the human clicks elsewhere, so a message goes to a session you did not mean to reach.
Always `--pane "$HERDR_PANE_ID"`.

## Trap: `pane_id` is the SOURCE, `neighbor_pane_id` is the answer

`herdr pane neighbor` returns both, and the obvious-looking key is you:

```json
{ "pane_id": "<pane>",            // <- YOU
  "neighbor_pane_id": "<pane>" }  // <- the buddy
```

Getting this wrong here is worse than in [[herdr-peek]]: peeking at yourself is
confusing, **messaging yourself is a prompt injected into your own session**.

## Related

[[herdr-peek]] looks without interrupting — prefer it when you only need to know what
the buddy is doing. [[herdr-buddy]] creates a buddy. [[herdr-pane-run]] is the right
tool for a bare shell. [[herdr]] is the CLI reference.
