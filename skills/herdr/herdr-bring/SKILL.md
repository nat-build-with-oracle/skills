---
name: herdr-bring
description: Ensure a herdr presence for any maw handle — resolves it via `maw locate`, opens its own herdr space, and resumes local Claude history when there is any, live or not. Kills a live maw tmux session only when one genuinely exists and is idle. Self-contained; works in any repo on any machine, no justfile recipe needed. Use when the user says "bring X into herdr", "move X from maw to herdr", "adopt X", or gives you a `maw ls` listing and asks to land some or all of it. Do NOT use to fork a session already inside herdr (use `just herdr-fork`), to cut a worktree (use /herdr-wt), or to take a GitHub issue (use /herdr-ticket).
argument-hint: "<maw-handle> [label] | (no args to list candidates)"
---

# /herdr-bring — land a maw handle into herdr

Puts a Claude Code process into its own herdr space for the repo a maw handle
resolves to, on **this pane's own herdr server**. A live maw tmux session is the
exception case, not the requirement — three landing modes:

- **live + transcript** → verify idle, kill the maw session, resume the same
  session id. Full history survives the move.
- **not live + transcript** → resume it directly. Nothing to kill.
- **neither** → start fresh.

"Bring" undersells it: this *ensures a herdr presence for this repo, using
whatever local history exists*. A handle that only ever existed as a registry
entry still lands, as a fresh start.

## Before anything

```bash
test "${HERDR_ENV:-}" = 1 || { echo "not inside a herdr pane — stop"; exit 1; }
```

If that fails, say so and stop. Do not drive a herdr session from outside one.

## Socket targeting

herdr sockets are per-server and ids do not collide across them. This targets
the **calling pane's own socket** (`$HERDR_SOCKET_PATH`, which herdr exports into
every pane it manages). An earlier version hardcoded a named session and broke
the moment that server was not running while the calling pane lived in
`default`. To target a different server on purpose, pass `--session <name>` to
each `herdr` call below, or export `HERDR_SOCKET_PATH` first.

Note the documented precedence: `--session` > `HERDR_SOCKET_PATH` > `HERDR_SESSION`
> default. A pane's own `HERDR_SOCKET_PATH` silently wins over `HERDR_SESSION`.

## Step 1 — list candidates

Show what exists before touching anything, even when the user named a target.
Confirming it exists costs nothing and catches typos before a kill.

```bash
maw ls --json | python3 -c "
import json,sys
for s in json.load(sys.stdin)['sessions']:
    print(f\"{s['session']:30} {s['status']:8} panes={s['panes']} agents={s.get('agents',0)}\")
"
```

`status` is **tmux pane recency**, not whether a turn is running. A session can
read `active` while sitting idle, or `stale` while a long turn runs. Never decide
safety from this field — step 3's spinner check is the real gate.

## Step 2 — resolve

```bash
maw locate <handle> --json
```

`maw locate` exits 1 on an ambiguous match while still printing valid JSON with
a `candidates` list, so capture it with `|| true` before reading. If the result
has `candidates`, print them and stop — do not pick one. If `repoPath` is empty,
report and skip; never guess a path.

## Step 3 — bring one

```bash
HANDLE=neo
LABEL="$HANDLE"          # or an explicit label; oracle repos read best as <name>-oracle

info=$(maw locate "$HANDLE" --json 2>/dev/null) || true
test -n "$info" || { echo "REFUSING: maw locate $HANDLE returned nothing"; exit 1; }
python3 -c "import json,sys; sys.exit(0 if 'candidates' in json.load(sys.stdin) else 1)" <<<"$info" && {
  echo "AMBIGUOUS — re-run with an exact name:"
  python3 -c "
import json,sys
for c in json.load(sys.stdin)['candidates']: print(f\"  {c['name']:20} ({c['kind']}) -> {c['action']}\")" <<<"$info"
  exit 1; }

repo=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('repoPath',''))" <<<"$info")
maw_session=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('session') or '')" <<<"$info")
test -n "$repo" || { echo "REFUSING: no repoPath for $HANDLE"; exit 1; }
echo "resolved  : $HANDLE -> $repo"

live=""
if [ -n "$maw_session" ] && tmux has-session -t "$maw_session" 2>/dev/null; then
  live=1
  # Busy check: Claude's own spinner line — a glyph, a gerund, an ellipsis, then "(<duration>".
  if tmux capture-pane -t "$maw_session" -p 2>/dev/null | tail -20 | rg -q '[✻✢✶◐●] .+…\s*\([0-9]'; then
    echo "REFUSING: $maw_session looks mid-turn — bring it only when idle"; exit 1
  fi
  echo "maw session: $maw_session (LIVE)"
else
  echo "maw session: ${maw_session:-<none>} (not live — checking local history)"
fi

# Newest transcript for that repo. Encoded path: leading / becomes -, then / and . become -.
enc=$(echo "$repo" | sed 's|^/|-|; s|[/.]|-|g')
claude_sess=$(ls -t "$HOME/.claude/projects/$enc"/*.jsonl 2>/dev/null | head -1 \
  | xargs -n1 basename 2>/dev/null | sed 's/\.jsonl$//')

pane=$(herdr workspace create --cwd "$repo" --label "$LABEL" --no-focus \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['root_pane']['pane_id'])")
echo "new pane  : $pane"

if [ -n "$live" ]; then
  test -n "$claude_sess" || { echo "REFUSING: $maw_session is live but no transcript for $repo — investigate before killing"; exit 1; }
  maw kill "$maw_session"; sleep 2
  herdr pane run "$pane" "claude --resume $claude_sess"
  echo "mode      : resumed (killed live maw session first)"
elif [ -n "$claude_sess" ]; then
  herdr pane run "$pane" "claude --resume $claude_sess"
  echo "mode      : resumed local history — nothing was live, nothing was killed"
else
  herdr pane run "$pane" "claude"; claude_sess="(new)"
  echo "mode      : fresh start — no maw session and no local transcript"
fi

for i in $(seq 8); do
  sleep 5
  agent=$(herdr pane get "$pane" 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane'].get('agent','none'))" 2>/dev/null || echo none)
  [ "$agent" = "claude" ] && break
done
[ "$agent" = "claude" ] || { echo "!! claude did not come up in $pane within 40s — herdr pane read $pane --source visible --lines 20"; exit 1; }
herdr agent rename "$pane" "$LABEL" >/dev/null 2>&1 || true
echo "OK — $claude_sess is live in $pane, named $LABEL"
```

**Kill before resume, never the other order.** Resuming while the old process
still lives puts two writers on one transcript and they interleave — this
happened for real. `sleep 2` lets the kill settle.

The 40s poll is not padding: direnv on a cold pane can take that long by itself.
If it exceeds it, read the pane rather than assuming failure.

## Step 4 — several

Run the same block per handle, printing a `── name ──` header for each. One
failure must not abort the rest; a busy session is skipped and reported.

**Never sweep every name from step 1 without the user naming them or explicitly
confirming a bulk sweep.** Landing a handle that turns out to be live still kills
its maw side — real, and only somewhat reversible: the tmux pane is gone and the
herdr copy is a resume of the same transcript, not a backup. You cannot know
which mode a name falls into until the script resolves it, so treat every name
in a batch as a potential live-kill.

## After landing

```bash
herdr workspace list
herdr agent list
```

State plainly which of the three modes happened — resumed a killed live session,
resumed local history with nothing killed, or started fresh with no prior history
at all. These are different outcomes. Never paraphrase a refusal as success, and
never call a fresh start "brought".

## Conflict = exit 2 = ASK, never decide

Two guards must run **before** the space is created:

| guard | catches |
|---|---|
| cwd already open | a second space for the same repo |
| label already taken | two *different* repos colliding on one name |

Both print `CONFLICT`, list options, and exit **2** — a distinct code meaning "a human
decides, then re-run". Exit 1 is a real error; exit 2 is not.

**On exit 2, present the options with `AskUserQuestion` and wait.** Do not pick one, do
not retry with a guessed label, do not set the override yourself:

- **focus** — use the existing space, create nothing
- **relabel** — re-run with a different label
- **rename** — fix the *existing* space's wrong name first, then re-run
- **anyway** — `HERDR_BRING_FORCE=1`, only when the user explicitly says so

The label guard exists because of a real miss on 2026-09-14: space `w1R` sat in
`<org>/pulse` but was **named** `pulse-oracle`. Landing the genuine
`<org>/pulse-oracle` passed the cwd check (different repo — correctly), created the
space, and only then failed at `herdr agent rename` with `agent_name_taken`, leaving a
live unnamed space behind. A guard that fires after the side effect is not a guard.

What that implies: a wrong label on one space silently blocks the *right* repo from ever
taking its own name. When the existing space is the mislabelled one, prefer **rename**
over **relabel**.

## Moving a body to ANOTHER herdr session (herdr to herdr, not tmux)

A herdr pane cannot cross sessions (`pane move` works inside one session). Moving a body means
starting the same conversation in the target session, ending the old one, and never having both alive.
Done 2026-10-05 for 5 live bodies (claude x4, codex x1); /herdr-info caught the one duplicate.

1. **Read the body.** Scheduled tasks or background work? (they block `/exit` with a dialog; see traps) Idle? (`herdr --session S agent list` -> status; never move a `working` body, its
   turn dies.) Its pid and exact flags (`herdr --session S pane process-info --pane P`, then
   `ps -o command -p PID`), conversation id (`agent_session.value`), cwd.
2. **New space in the target session at that cwd.** `herdr --session T workspace create --cwd D --label L`,
   or for a worktree that should nest under its repo's main space
   `herdr --session T worktree open --workspace <main space> --path D`.
3. **Arm it.** `herdr --session T pane run NEW 'while kill -0 PID 2>/dev/null; do sleep 1; done; claude <same flags> --resume ID'`
   (codex: `codex resume ID`, same bypass flags). The wait loop is what guarantees one copy.
4. **End the old one.** `herdr --session S agent prompt OLD "/exit"` (codex: `/quit`).
5. **Check.** `/herdr-info <oracle>` -> `warnings: none`; re-apply the agent name (it resets on resume);
   close the old space only when EVERY pane in EVERY tab is a bare `zsh`: atlas lived as a second tab inside
   another space, and closing that space would have killed it.

| trap | avoid |
|---|---|
| `/exit` stops at "You have N unsent feedback draft(s). Enter to review & send, Esc to discard and exit": the process stays alive, the armed pane keeps waiting (atlas, 2026-10-05) | the human chooses; never press either for them (Enter sends feedback outward, Esc discards a draft) |
| `/exit` stops at "Background work is running … 1. Exit and stop tasks · 2. Move to background and exit · 3. Stay" (homelab, 2026-10-05: a /loop every 15 min running /cpu-ram-doctor and /cpu-kill) | never pick 2: the old process keeps running, so the resumed copy becomes a second writer. Pick 1 only with the owner's OK, then re-create the same scheduled task in the new copy; to back out, pick 3 (Stay) and close the armed pane |
| a body that holds a live Discord connection (`--channels plugin:discord`; `DISCORD_STATE_DIR` and `DISCORD_BOT_TOKEN` come from the folder's `.envrc`) | start the new pane in the same folder so direnv gives the same env; the old process must be gone first (one connection per bot) |
| pane ids repeat across sessions (`<pane>` existed in two) | always `--session`; address by folder or agent name |
| `maw herdr join` / `break` act on the tab of the pane they run in | they cannot do this move; use the steps above, or `/herdr-room` for rooms inside one session |

## Traps

- **The agent name is cleared when the pane's occupant is replaced.** Measured
  2026-09-14: after a resume re-initialised Claude, the workspace *label*
  survived and the agent *name* went to `None`. The rename at the end can
  therefore come undone a minute later — re-apply with
  `herdr agent rename <pane> <label>` and address panes by `pane_id`, not name.
- **A plain workspace has NO `worktree` object.** When checking "is this repo
  already open?", match on each **pane's `cwd`**, not on
  `workspace.worktree.checkout_path`. Only worktree-backed spaces carry a
  `worktree` object at all; a space made by `herdr workspace create` has none,
  so checkout_path matching silently returns nothing and you create the
  duplicate you were guarding against. Hit for real on nexus-oracle, 2026-09-14.

  ```bash
  herdr pane list | python3 -c "
  import json,sys
  repo=sys.argv[1]
  print([p['workspace_id'] for p in json.load(sys.stdin)['result']['panes'] if p.get('cwd')==repo])" "$repo"
  ```

- **`maw ls`'s active/idle/stale is not a busy signal** — see step 1.
- **Errors are JSON on stderr with exit 1** for server-side failures, and some
  paths still exit 0 with an error body. Parse the body, not `$?`.
- **The transcript lookup takes the newest `.jsonl` for the repo path.** A repo
  with a fork or a worktree copy running concurrently may not give you the one
  in the named maw pane. Cross-check with `maw peek <handle>`.
- **The spinner regex is tuned to this fleet's status line.** If it ever refuses
  an obviously idle session, or waves through a working one, say so — the
  pattern needs updating, not a silent override.

## What this does NOT do

- Does not touch a session already inside herdr (use `just herdr-fork`); to move a herdr body to another
  herdr session see § Moving a body to ANOTHER herdr session.
- Does not create a worktree — the space checks out the repo's own working
  directory. For a worktree, `/herdr-wt`.
- Does not restart or fix a stuck maw session. If the busy check refuses one
  whose agent actually crashed mid-turn, investigate with `maw peek` first.

## Related

- `/herdr-wt` — worktree per task, `wt/<oracle>-<slug>-<date>`
- `/herdr-ticket` — a GitHub issue in its own worktree and space
- `/herdr-incubate` — another oracle's topic from inside the current repo
- `herdr` — the CLI reference
- `/herdr-room` — pull live agents into one room and back out, inside one session
- `/herdr-info` — where every body of an oracle (or a space) runs; run it after any move
