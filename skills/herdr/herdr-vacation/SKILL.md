---
name: herdr-vacation
description: Park idle agents before the human goes away — for the named repos (or all), find every herdr pane whose agent has been idle longer than N hours (default 3), quit it (transcript kept, resumable) and close its space. Parks only; never removes a worktree, commits, pushes or deletes. Skips anything working, blocked, or whose last message is a question to the human, and lists those instead. Use when the user says "vacation", "going away", "close what's idle", "not active for 3h close", "park the fleet", or /herdr-vacation. Do NOT use to remove worktrees (use /herdr-clean-up-sync or /herdr-dissolve) or to wake agents back up (use fleet resume / /herdr-bring).
argument-hint: "[repo ...] [--hours N] [--host H]"
---

# /herdr-vacation: park idle agents, keep everything

> **Needs `fleet`.** This skill drives the `fleet` CLI from
> [nat-build-with-oracle/herdr-fleet](https://github.com/nat-build-with-oracle/herdr-fleet).
> Install: `git clone https://github.com/nat-build-with-oracle/herdr-fleet.git && cd herdr-fleet && mkdir -p ~/.local/share ~/.local/bin && ln -sfn "$PWD" ~/.local/share/herdr-fleet && ln -sfn ~/.local/share/herdr-fleet/fleet.ts ~/.local/bin/fleet && bun install`
> then check with `fleet help | head -3`.

The goal: when Nat comes back, the sidebar shows only what was live, and nothing he
cared about is gone. Parking means quitting the idle agent with ctrl-c and closing its
space. It does **not** mean removing the worktree, committing, or touching files.
`fleet resume <path>` brings any of them back on the same session.

## 1. Measure idleness per pane

The idle time is how long ago the agent's own transcript was last written. Not the git
log, and not the sidebar mark.

```bash
now=$(date +%s)
herdr pane list | jq -r '.result.panes[] | [.workspace_id,.pane_id,(.agent//"shell"),.agent_status,
    (.agent_session.value//"-"),(.foreground_cwd//.cwd)] | @tsv' \
| rg '<repo1>|<repo2>' | while IFS=$'\t' read ws id ag st sid cwd; do
  enc=$(echo "$cwd" | sed 's|^/|-|; s|[/.]|-|g')
  f=~/.claude/projects/$enc/$sid.jsonl; [ -f "$f" ] || f=$(ls -t ~/.claude/projects/$enc/*.jsonl 2>/dev/null | head -1)
  t=$(stat -f %m "$f" 2>/dev/null || echo 0)          # Linux: stat -c %Y
  echo "$ws $id $ag $st idle=$(( (now-t)/3600 ))h $cwd"
done
```

For a bare shell pane (no agent), use the newest transcript in that directory. If there
is none, the space is only a leftover shell: park it.

## 2. Classify

| State | Action |
|---|---|
| agent `working` or `blocked` | **keep**, and list it |
| idle ≥ N h, last message finished ("done", "nothing pending", a report) | **park** |
| idle ≥ N h, last message a **question** to the human | **keep**, and list the question; Nat answers it on return |
| idle < N h | keep |
| bare shell, no agent | park (close the space) |

Read the last message before parking: `herdr pane read <pane> --source recent-unwrapped --lines 40 | tail`.

## 3. Show the plan, then park

Show one table first: pane, repo or worktree, idle hours, last line, and the action.
Then, for each row marked park:

```bash
fleet kill <pane>                          # gentle: ctrl-c until the Claude pid is gone
herdr workspace close <ws>                 # only if no agent is left in that space
```

`fleet kill` quits the agent; its transcript stays. Close the space only when every
pane in it is parked.

## 4. Report for the return

List three groups:
- **parked**: pane, repo, session id, and `fleet resume <path>` to bring it back
- **kept, working**
- **waiting on Nat**: each question, quoted

Uncommitted files in parked checkouts stay where they are. Name the counts so they
aren't forgotten, for example "transcriber main: 11 uncommitted".

## Guards

- Parking never deletes. If the user wants worktrees gone, that's a separate
  `/herdr-clean-up-sync`, run after reading.
- Never park this session's own pane, or a pane whose agent is `working`.
- `--host H`: run the same logic on the remote host over ssh with `bash -lc`. Remember
  white's `stat -c` and its login-shell PATH.
