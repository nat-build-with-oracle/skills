---
name: herdr-neighbors
description: Survey every pane around you before you touch any of them — all four directions plus the whole workspace, each reported as agent-or-shell with its name, kind, status and cwd. Read-only. Use when the user says "check neighbours", "who is around", "who else is here", "what panes are open", "is anyone next to me", or before any fan-out where you are about to message or run something in more than one pane. To read ONE buddy's scrollback use /herdr-peek; to message one use /herdr-hey.
argument-hint: ""
---

# /herdr-neighbors — know who is around before you touch anything

Read-only. Sends nothing anywhere. This is the survey you run **before** [[herdr-hey]]
or [[herdr-pane-run]], not instead of them.

The one question it answers that nothing else does: **which panes hold agents and which
hold shells**, for every pane near you at once. Get that wrong and a shell command lands
in an agent's prompt, or prose executes in a shell.

## Run it

```bash
me="${HERDR_PANE_ID:-$(herdr pane current | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane']['pane_id'])")}"
echo "me = $me"

# 1. adjacency — who is literally beside me, per direction
for d in left right up down; do
  n=$(herdr pane neighbor --pane "$me" --direction "$d" 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['neighbor'].get('neighbor_pane_id',''))")
  printf '  %-6s %s\n' "$d" "${n:-—}"
done

# 2. occupancy — every pane in my workspace, agent or shell
herdr pane list | python3 -c "
import json,sys,subprocess
me=sys.argv[1]; ws=me.split(':')[0]
agents={}
for a in json.loads(subprocess.run(['herdr','agent','list'],capture_output=True,text=True).stdout)['result']['agents']:
    agents[a['pane_id']]=a
for p in json.load(sys.stdin)['result']['panes']:
    if p.get('workspace_id')!=ws: continue
    pid=p['pane_id']; a=agents.get(pid)
    who=f\"{a['agent']} '{a.get('name') or '(unnamed)'}' [{a['agent_status']}]\" if a else 'bare shell'
    print(f\"  {pid}{' (me)' if pid==me else ''}  {who}  {p.get('cwd','')}\")
" "$me"
```

## Read BOTH lists — they answer different questions

| list | answers |
|---|---|
| adjacency (`pane neighbor`) | which pane is *beside* me, per direction — what `/herdr-peek right` will target |
| occupancy (`pane list` + `agent list`) | who exists at all, including panes that are **not** a directional neighbour |

They disagree routinely, and that is not a bug. Measured 2026-09-19: `<pane>` and `<pane>`
were the only two panes in the workspace, so occupancy showed both — but adjacency
showed `right → <pane>` and **nothing** for left, up, down. A pane can exist in the tab
and be reachable by no direction at all once the layout has more than two panes.

Never substitute one for the other. "It is the only other pane, so it must be my
neighbour" holds in a two-pane tab and breaks silently in three.

## `herdr agent list` is the check that matters — not `pane list`

`pane list` gives you `cwd`, and **cwd does not say whether anyone is home**. A pane
sitting in a repo directory looks identical whether an agent occupies it or it is an
idle shell.

Measured 2026-09-19: `herdr pane run <pane> 'npx wrangler tail …'` was aimed at a pane
believed free, after checking `pane list` and reading only the cwd. It held a live
Claude agent. The command arrived as a **user turn** and that agent began acting on it.

```
pane holds an agent  ->  herdr agent prompt <name>    (a message)
pane holds a shell   ->  herdr pane run <pane> 'cmd'  (a command)
```

## Expect the layout to flicker

The same adjacency call returned `<pane>`, then nothing, then `<pane>` again inside a
minute while the pane existed the whole time — the layout was mid-change as the human
moved focus. **One empty survey means "not right now", not "nobody is there."** Re-run
before concluding you are alone.

## Traps

**`--current` is not uniform across subcommands** (herdr 0.9.1):

| call | resolves to |
|---|---|
| `herdr pane current` | your own pane — stable |
| `herdr pane neighbor --current` | the **focused** pane — moves when the human clicks |

Use `--pane "$HERDR_PANE_ID"` everywhere. Found by glyph-codex, 2026-09-19.

**`pane_id` is the source, `neighbor_pane_id` is the answer.** `pane neighbor` returns
both; the obvious key is you. A `.get('pane_id')` fallback surveys yourself.

**The key is ABSENT when there is no neighbour** — the response drops to
`direction`, `layout`, `pane_id`, so `n['neighbor_pane_id']` raises `KeyError` instead
of reporting "none". Always `.get(..., '')`.

**Names are not durable.** herdr's docs: *"A name follows the current pane occupant and
is cleared when that agent exits, is released, or is replaced."* A name that vanishes
fails loudly (`agent_not_found`); a stale pane id delivers to whoever inherited it,
silently. Re-survey after any gap rather than reusing a name you cached.

## Related

[[herdr-peek]] reads one buddy's scrollback. [[herdr-hey]] messages one. [[herdr-buddy]]
creates one. [[herdr-pane-run]] runs a command in a bare shell pane. [[herdr]] is the
CLI reference.
