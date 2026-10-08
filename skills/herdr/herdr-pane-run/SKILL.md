---
name: herdr-pane-run
description: Run a long command in a herdr pane so the human watches it live, then have the pane read its own output and send the real result plus exit code back to the agent. Use for indexes, builds, test suites, migrations, long greps — anything slow enough that the agent's own Bash tool hides all progress until it exits. Do NOT use for quick commands the agent should just run itself.
installer: create-shortcut
created_at: 2026-09-18T19:57:52+07:00
created_session: 04d1d650
---

# /herdr-pane-run

Run it where the human can see it. Get the same thing back.

## The problem

An agent's `Bash` tool shows **nothing until the command exits**, and piping through
`tail` makes it worse — `tail` buffers to EOF, and progress written with `\r` (one
overwritten line) emits no newlines at all, so the captured log stays empty the whole
run.

Measured for real: a 10,058-file index printed its banner, then nothing for minutes.
It looked frozen twice. It wasn't — the output was structurally invisible.

`run_in_background: true` already stops the agent blocking. What it does NOT do is let
the human see anything. This gives both: **you watch it live, the agent gets the result.**

## Step 0: Init

```bash
date "+🕐 %H:%M %Z (%A %d %B %Y)" && herdr pane list 2>/dev/null | head -1
```

## The pattern

The pane runs the command normally, then **reads its own scrollback** and forwards it:

```bash
herdr pane run <PANE> '<CMD>; RC=$?; \
  herdr agent prompt <MY-AGENT-NAME> "PANE <PANE> rc=$RC
$(herdr pane read <PANE> --source recent-unwrapped --lines 14 2>/dev/null | tail -8)"'
```

**Scale the window to the pane.** `--lines 14 | tail -8` assumes a tall pane. In a 4-row
strip the real output is 2 lines, so the window reaches up into direnv noise and the
echoed command itself. Rough rule: `--lines (rows + 4) | tail -(rows - 1)`, and drop
prompt lines. Seen for real in a 86x4 strip:

```
direnv: loading .../.envrc          <- noise
neo-herdr-14sep-mon2026 on ...      <- prompt
<apped --lines 14 2>/dev/null ...   <- the command, echoed and wrapped
indexing 12/12 ...                  <- the actual output
scanned 10701 tracked files
```
```

Nothing is redirected. Output lands on the terminal exactly as it normally would, the
human sees it live, and the pane then captures what is on screen.

| part | why |
|---|---|
| no redirect, no `tee` | the human must SEE it — that is the whole point of a pane |
| `RC=$?` on the very next statement | anything in between overwrites it |
| `herdr pane read <PANE>` | the pane reads ITSELF — captures rendered output, `\r` progress already collapsed |
| `\| tail -8` | the ANSWER is at the end for builds/tests/indexes |
| `herdr agent prompt <me>` | the pane pushes; the agent never polls |

### Why not redirect to a file

An earlier version used `> /tmp/out 2>&1` and then sent `tail` of the file. It worked,
and it was wrong: **the pane showed nothing**, so the human gained nothing over
`run_in_background`.

Fixing that with `tee` introduces a worse bug. Probed in a real zsh pane:

```
(exit 7) | tee f ; echo $?              -> 0      # FALSE SUCCESS
set -o pipefail; (exit 7) | tee f; echo $?  -> 7      # correct
```

A pipe makes `$?` report `tee`, so a failing command reports `rc=0`. Reading the pane
instead never creates the pipe, so plain `$?` is correct.

## head or tail?

**`tail`.** For everything this skill is for, the answer is at the end. Measured on a
real index log:

```
head -c 220  ->  ...banner... 1264.84s system        <- cut mid-number
tail -c 220  ->  6:48.91 total / [exited with code 0]    <- the actual result
```

Use `head` only when the command RANKS its output — a search, where the best hit is first.

## Step 1: Know where you are, before you touch any pane

Never send a command to a pane you have not identified. **A pane with an agent in
it is not free** — `herdr pane run` types into that agent's prompt, not a shell, so
you hijack another Claude session instead of running anything.

```bash
# Who and where am I?
herdr pane current | python3 -c "
import json,sys
p = json.load(sys.stdin)['result']['pane']
print('pane =', p['pane_id'])
print('tab  =', p['tab_id'])
print('ws   =', p['workspace_id'])
print('cwd  =', p.get('cwd',''))"
```

```bash
# What else is in MY tab? Substitute the tab id printed above.
TAB=<tab>
herdr pane list | python3 -c "
import json,sys
panes = [p for p in json.load(sys.stdin)['result']['panes'] if p['tab_id']=='$TAB']
print('panes in tab:', len(panes))
for p in panes:
    print(' ', p['pane_id'], p.get('agent','(shell)'), p.get('agent_status','-'))"
```

## Step 2: Reuse the labelled run pane, or make one

The expected starting state is **one pane — you**. Split it to the right; the new
pane is a bare shell with your cwd inherited, and it sits where the human can watch
it next to the conversation.

| what you find | what to do |
|---|---|
| **a pane labelled `run` in this tab** | **reuse it.** Do not split again — this is the common case |
| **1 pane** (just you) | `herdr pane split --current --direction right --ratio 0.9`, then label it |
| **2+ panes, no `run` label** | `herdr pane split --current --direction down --ratio 0.9`, then label it |

Splitting is always safe — it creates a new pane. What is never safe is **reusing a pane
that holds an agent or a long-running process** (a dev server, a watcher): `pane run`
types into it. Only reuse a pane you labelled `run` yourself.

### Label the run pane, or you will spawn a new one every time

`pane rename <id> run` sets a `label`. Without it there is no way to tell "the idle
shell I made for runs" from "a shell running vite", so each invocation splits again and
the tab fills up with forgotten strips.

```bash
# reuse if it exists, otherwise create and label it
RUN_PANE=$(herdr api snapshot | python3 -c "
import json,sys
tab='$TAB'
for p in json.load(sys.stdin)['result']['snapshot']['panes']:
    if p.get('tab_id')==tab and p.get('label')=='run': print(p['pane_id']); break")

if [ -z "$RUN_PANE" ]; then
  RUN_PANE=$(herdr pane split --current --direction down --ratio 0.9 --no-focus \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane']['pane_id'])")
  herdr pane rename "$RUN_PANE" run >/dev/null
fi
echo "run pane: $RUN_PANE"
```

**`label` is not in `pane list`.** Measured 2026-09-20: `pane rename` returns it and
`pane get` and `api snapshot` both carry it, but `pane list` omits the field entirely —
a `pane list`-based check silently never matches, and you split forever.

### `--ratio` is the share of the pane you split FROM

Not the new one. Measured 2026-09-20 on a 158×45 tab:

```
split right --ratio 0.1   ->  me 9x45   NEW 77x45     <- backwards from what you want
split right --ratio 0.9   ->  me 77x45  NEW 9x45      <- run pane gets 10%
```

So a **small run pane needs a LARGE ratio**. Getting this backwards silently shrinks
the agent's own pane to 9 columns instead.

### Prefer `down` once there are two panes

Same measurement, splitting the same pane:

```
right --ratio 0.9  ->  run pane   9 x 45    9 columns: every line wraps to confetti
down  --ratio 0.9  ->  run pane  86 x  4    full width, 4 rows: actually readable
```

A narrow column is worse than useless for watching a build — the point of the pane is
that the human can read it. Height costs nothing here because the capture does not
depend on what is visible: `pane read` takes scrollback, and `recent-unwrapped` undoes
the wrapping, so a 4-row strip still yields a clean `tail -8`.

Verified 2026-09-19: from `<pane>` this returns `<pane>`, `agent_status: unknown`
(a bare shell, which is what you want), same `tab_id`, cwd inherited.

`--ratio 0.9` leaves the agent 90% and gives the run pane 10%. `--direction` accepts
only `right` or `down`. Use `down` whenever the tab already has two panes: a bottom
strip keeps full width, where a third column would be ~9 characters wide.

## Step 3: Claim a reply name

An unnamed agent signs as a pane id, and pane ids are **reassigned when herdr
restarts** — the reply then goes to whoever inherited it.

```bash
MYPANE=$(herdr pane current | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['pane']['pane_id'])")
ME=$(herdr agent list | python3 -c "
import json,sys
for a in json.load(sys.stdin)['result']['agents']:
    if a['pane_id']=='$MYPANE': print(a.get('name') or '')")
[ -n "$ME" ] || herdr agent rename "$(herdr pane current \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['pane']['pane_id'])")" \
  <stable-name>
```

## Step 4: Fire, using **The pattern** above

Build the one-liner with `$RUN_PANE` and `$ME`. Single-quote the outer command so
`$RC` and `$(…)` expand in the pane, not in your shell.

## Step 5: Keep working — do not poll

The reply arrives on its own as a mid-turn injection. `sleep N; herdr pane read`
throws away the entire advantage.

## Step 6: Close the pane when the work is done

```bash
herdr pane close "$RUN_PANE"
```

Leave the layout as you found it unless the human asked for a persistent run pane.
Splits accumulate; three forgotten ones make the tab unreadable.

---

## Finding the pieces

```bash
# panes in this tab; a bare shell shows agent "(shell)"
herdr pane list | python3 -c "
import json,sys
for p in json.load(sys.stdin)['result']['panes']:
    print(p['pane_id'], p.get('agent','(shell)'), p.get('cwd','')[-40:])"

# the agent's OWN name — this is the reply address. Match YOUR pane id, never
# `focused`: focus follows the human's cursor, so another pane can be the focused one.
MYPANE=$(herdr pane current | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['pane']['pane_id'])")
herdr agent list | python3 -c "
import json,sys
for a in json.load(sys.stdin)['result']['agents']:
    if a['pane_id']=='$MYPANE': print(a.get('name') or a['pane_id'])"
```

**Claim a name first.** An unnamed agent signs as a pane id, and pane ids are reassigned
when herdr restarts — the reply then goes to whoever inherited it:

```bash
herdr agent rename "$(herdr pane current --current | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')" <stable-name>
```

A reboot wipes the name. Re-claim it before relying on a reply address.

## Variant: the run pane in its own tab

If the human wants the agent's tab left alone, put the run pane in a second tab of
the same workspace. The pattern does not change. `pane read` and `agent prompt` work
across tabs, and the human switches tabs to watch.

```bash
WS=$(herdr pane current | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['pane']['workspace_id'])")
# reuse a run pane anywhere in this workspace first, the same rule as Step 2
RUN_PANE=$(herdr api snapshot | python3 -c "
import json,sys
for p in json.load(sys.stdin)['result']['snapshot']['panes']:
    if p.get('workspace_id')=='$WS' and p.get('label')=='run': print(p['pane_id']); break")
if [ -z "$RUN_PANE" ]; then
  RUN_PANE=$(herdr tab create --workspace "$WS" --label run --cwd "$PWD" \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['root_pane']['pane_id'])")
  herdr pane rename "$RUN_PANE" run >/dev/null
fi
```

When the work is done, close the whole tab instead of only the pane (Step 6):
`herdr tab close "$(herdr pane get "$RUN_PANE" | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['pane']['tab_id'])")"`.

`tab create` returns `.result.root_pane.pane_id`, not `.result.pane`. Tested
2026-10-08: `<pane>` in a new tab `<tab>`, round trip `rc=0`.

It is **not a mirror**. The output exists only in the run tab, and herdr has no
built-in pane mirroring. A real mirror means a second pane that keeps re-reading the
run pane on a loop, which is a poll, so do not build one unless the human asks for it.

## Map the workspace: structure, what is running, latest output

Before you reuse, close, or report on a pane, print the whole workspace. The script
lists every tab and pane with its label, agent status and foreground process, plus the
last lines of each `run` pane:

```bash
WS=$(herdr pane current | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['pane']['workspace_id'])")
herdr api snapshot | python3 -c "
import json,sys
for p in json.load(sys.stdin)['result']['snapshot']['panes']:
    if p['workspace_id']=='$WS': print(p['tab_id'], p['pane_id'], p.get('label') or '-', p.get('agent_status','-'))" |
while read TAB PANE LABEL STATUS; do
  FG=$(herdr pane process-info --pane "$PANE" | python3 -c "
import json,sys
i=json.load(sys.stdin)['result']['process_info']
g=i['foreground_process_group_id']
lead=[p for p in i['foreground_processes'] if p['pid']==g]
print('idle shell' if g==i['shell_pid'] else (lead[0].get('cmdline') or lead[0]['name'])[:50] if lead else 'pgid %s' % g)")
  echo "$TAB  $PANE  label=$LABEL  agent=$STATUS  fg: $FG"
  [ "$LABEL" = run ] && herdr pane read "$PANE" --source recent-unwrapped --lines 6 2>/dev/null | tail -3 | sed 's/^/      | /'
done
```

Real output (2026-10-08):

```
<tab>  <pane>  label=-  agent=working  fg: caffeinate -i -t 300
<tab>  <pane>  label=run  agent=unknown  fg: idle shell
      | worktree-calm-meadow-eea9 on  worktree/calm-meadow-eea9 [!] ...
      | ❯
```

How to read it:

- **`fg: idle shell`** means the shell is the foreground process, so the run pane is
  free. Anything else is the command that is still running.
- **`fg` is the process-group leader**, the pid equal to `foreground_process_group_id`.
  Never take `foreground_processes[0]`: that list holds the whole group, so an agent
  pane lists every MCP child, and the first entry was `caffeinate`, not `claude`.
  Some entries have no `cmdline` key, which is why the script falls back to `name`.
- **For agent panes, trust `agent=`.** It can still say `unknown` for a few seconds
  after `claude` starts in a pane.
- **`process-info` takes `--pane <id>`**, not a bare id (`unknown option: <pane>`).
- To look at one pane: `herdr pane read <PANE> --source recent-unwrapped --lines 20`.
  Use `--source visible` to see exactly what is on screen now.
- For every workspace on the machine, drop the `workspace_id` filter. Expect noise:
  one server can hold 20+ workspaces.

## Traps

- **`label` is missing from `pane list`** — use `pane get` or `api snapshot` to find
  the pane you labelled `run`, or you will split a new one every single time.
- **A bare shell is not an agent.** `herdr agent prompt` fails against one; use
  `herdr pane run`. Only the *reply target* has to be an agent.
- **Single-quote the outer command** so `$RC` and `$(…)` expand in the PANE, not in the
  agent's shell before sending.
- **Exit code alone is not a result.** `rc=0` on a suite that ran zero tests is a pass
  proving nothing. Send output; read the output.
- **`--ratio` is the FIRST child's share** — the pane you split from. A 10% run pane
  needs `--ratio 0.9`, not `0.1`.
- **Do not `| tail` the command itself** inside the pane — that reintroduces the
  buffering bug the pane exists to avoid. Let it print, then read the pane.

## Actually going fast

Fire and keep working. The message arrives on its own as a mid-turn injection — do NOT
follow up with `sleep N; herdr pane read`, which throws the advantage away.

|  | agent blocks? | human sees live? |
|---|---|---|
| plain `Bash` | yes | no |
| `Bash run_in_background` | no | no |
| **this** | **no** | **yes** |

## When NOT to use it

Anything the agent can run in a second. The round trip costs more than the command, and
it puts output somewhere the transcript will not keep.

## Instructions

1. `herdr pane current` — know your own pane, tab, and workspace first. To see every
   tab, what each pane is running, and the run pane's latest output, use
   **Map the workspace**.
2. Count the panes in **your tab**. Expect exactly one: you.
3. Look for a pane labelled `run` in your tab (`api snapshot`, not `pane list`).
   Found → reuse it. Not found → split (`right --ratio 0.9` if you are alone,
   `down --ratio 0.9` otherwise) and `herdr pane rename <id> run`.
4. Claim a stable agent name if you have none; pane ids are reassigned on restart.
5. Build the one-liner from **The pattern**, single-quoted.
6. Fire it. Keep working. Do not poll.
7. When the message lands, **read the output**, not just `rc`, and report what it says.
8. Close the run pane.

---

ARGUMENTS: 
