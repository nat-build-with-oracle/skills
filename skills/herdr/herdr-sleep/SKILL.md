---
name: herdr-sleep
description: Put herdr spaces to sleep so they wake up exactly where they were. For each target it takes a bookmark from the agent (what it was doing, what is next), writes a wake card (cwd, agent kind, session id, its own argv, channel on/off, and the command of every non-agent pane such as dev servers), then quits the agent (transcript kept), stops the servers and closes the space. `/herdr-sleep wake` replays the cards. Use when the user says "sleep", "herdr sleep", "put X to sleep", "pause this space", "shut it down for now, bring it back later", "/sleep". Do NOT use to delete worktrees (use /herdr-dissolve or /herdr-clean-up-sync) or for a bulk idle sweep before being away (use /herdr-vacation, which parks without bookmarks or server replay).
argument-hint: "<space|pane|repo|self> [...] | wake [card ...] | list"
---

# /herdr-sleep: park a space with a way back in

> **Needs `fleet`.** This skill drives the `fleet` CLI from
> [nat-build-with-oracle/herdr-fleet](https://github.com/nat-build-with-oracle/herdr-fleet).
> Install: `git clone https://github.com/nat-build-with-oracle/herdr-fleet.git && cd herdr-fleet && mkdir -p ~/.local/share ~/.local/bin && ln -sfn "$PWD" ~/.local/share/herdr-fleet && ln -sfn ~/.local/share/herdr-fleet/fleet.ts ~/.local/bin/fleet && bun install`
> then check with `fleet help | head -3`.

`/herdr-vacation` parks whatever is idle and keeps nothing but the transcript. Sleep is
per space and keeps everything needed to come back in one step:
- the agent's own note on where it was
- the exact session id and flags
- whether the fleet channel was on
- **the servers running in the other panes**

Waking replays all of it.

Wake cards live in `~/.local/state/herdr-sleep/<YYYY-MM-DD>/<label>.json`, one per space.
They stay outside every repo, because a card holds paths and pane commands, not secrets.
Never write env values into a card.

## Sleep

For each target (a space id, pane id, repo or worktree name, or `self`):

1. **Resolve** the space and its panes: `herdr pane list`, filtered to the workspace.
   If the agent's status is `working` or `blocked`, **stop** for that target and say
   why. Never put an agent to sleep mid-turn.
2. **Bookmark.** Ask the agent (`fleet send <pane>`, never `herdr agent prompt`) to reply in at most 4 lines:
   - what it was doing
   - its state (committed / pushed / uncommitted)
   - the next step
   - any question it is waiting on

   Read the reply with `fleet watch <pane>` and then `fleet tail <pane>`. If the agent
   ended on a question, keep that question in the card.
3. **Write the card:**
   ```json
   {
     "slept": "2026-09-24T14:40+07:00", "host": "m5",
     "space": {"id": "<space>", "label": "my-app-oracle", "cwd": "$(ghq root)/.../my-app-oracle"},
     "agent": {"pane": "<pane>", "kind": "claude", "session": "<session>",
               "argv": ["claude","--resume","…","--dangerously-load-development-channels","server:fleet"],
               "channel": true, "name": "my-app", "token": "<token-name>"},
     "panes": [{"pane": "<pane>", "cwd": "…/my-service", "cmd": "<foreground argv>", "role": "server :8421"}],
     "bookmark": "<the agent's 4 lines>",
     "git": {"branch": "main", "ahead": 0, "dirty": 3}
   }
   ```
   - The agent's argv and session come from its process: `herdr pane process-info --pane <p>`, then `~/.claude/sessions/<pid>.json`. `fleet snapshot` records the same data.
   - Server panes: take the foreground argv from `process-info`. Record `cwd`, and the `.envrc` or env **file path** it was sourced from, never the values.
   - Token: the **name** only (`CLAUDE_TOKEN_NAME`), never the value.
4. **Stop, in this order:**
   1. `fleet kill <agent-pane>`: ctrl-c until the Claude pid is gone.
   2. ctrl-c each server pane (`herdr pane send-keys <p> ctrl+c`), then check the port is free (`lsof -iTCP:<port> -sTCP:LISTEN`).
   3. `herdr workspace close <space>`.
5. **Report** one row per space: card path, bookmark (the first line), what stopped, and the wake command.

`self` writes your own card, then asks the human (or the lead) to run the stop steps. You
can't quit yourself and also finish the job.

## Wake: `/herdr-sleep wake [label ...]`

`/herdr-sleep list` shows the cards, newest first. For each card to wake:

1. **Open the space:**
   - For a worktree: `herdr worktree open --cwd <cwd> --trust-repository`, which keeps the sidebar nesting.
   - For a main checkout: `herdr workspace create --cwd <cwd> --label <label>`.
2. **Agent:** `herdr pane run <pane> 'echo "TOK=$CLAUDE_TOKEN_NAME"'` (warms direnv), then `herdr pane run <pane> "claude --resume <session>"`. If `channel` was true: `fleet restart <pane> --channel`. Rename it back with `herdr agent rename <pane> <name>`.
3. **Servers:** split a pane per server, and `pane run` its recorded command in its recorded cwd, with its recorded env file sourced. Then check each port answers.
4. **Brief it:** `fleet send <pane> "Woke from sleep. Your bookmark: <bookmark>"`, so it starts from its own note.
5. Mark the card `"woke": "<time>"`. Never delete cards; they are the sleep log.

## Guards

- Sleep never commits, pushes, removes a worktree or deletes files. Uncommitted work
  stays on disk, and the card records the count.
- Never write secrets into a card: env **file paths** and token **names** only.
- A server that won't stop within 5 s is reported, not `kill -9`ed.
- Waking an agent whose transcript is missing from the live `~/.claude/projects` (it was
  archived): copy it back from `projects-archive/` (a copy, not a move), as was done for
  my-app, then resume.
