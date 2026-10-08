---
name: herdr-handover
description: Hand ownership of a live surface (a repo directory, a running server, a browser extension) to a peer agent in another herdr pane, then watch it without interfering. Use when the user says "hand over to", "let him take it", "that's his now", "you just peek", or when two agents are about to edit the same files. Produces a handover message carrying live process state and uncommitted work, then switches you to read-only observation. NOT for session-to-session handoff — that is /forward.
argument-hint: "<agent-name> <surface>"
---

# /herdr-handover — give it away cleanly, then watch

Two agents editing one surface corrupt each other quietly. This is the protocol
for transferring it: state what is live, state what is uncommitted, then stop
touching it and observe.

Distinct from [[forward]], which hands *your own session* to the *next* session.
This hands *one surface* to a *peer running right now*.

## The three parts, in order

Skipping any one of them is how a handover turns into two agents surprised by
each other an hour later.

### 1. Measure what is actually live — do NOT describe it from memory

```bash
# processes you started that outlive your involvement
lsof -i:<port> -P -n | rg LISTEN
ps -p <pid> -o pid,ppid,etime,command

# its own health surface, if it has one
curl -s --max-time 3 127.0.0.1:<port>/health

# work in flight that they will otherwise clobber or lose
git status --short <surface>/
```

A handover that says "the server is running" is useless. One that says
`pid 86250, bun run server.ts, up 26m, log /tmp/aria-proxy.log` lets them kill
it without asking you.

**Pre-empt the thing that will look broken.** Measured 2026-09-19: `lsof -ti`
on the port returned two pids and looked like a duplicate server. One was the
*browser holding the client end* of the socket. Saying so in the handover cost
one line and saved them the same five-minute detour.

### 2. Send it — with measurements, not conclusions

```bash
herdr agent prompt <their-name> "<message>"
```

Use [[herdr-hey]]'s discipline. What a handover must carry, in this order:

| section | why |
|---|---|
| **explicit stop** | "I have stopped editing, reloading, restarting. Nothing of mine is in flight." Ambiguity here is the whole failure mode. |
| **live processes** | pid, command, uptime, log path, and *who started it* — so they may kill it |
| **uncommitted work** | `git status --short` verbatim; say whether it is theirs to keep or discard |
| **measurements behind your edits** | the numbers, so they can re-derive rather than trust you |
| **what stays yours** | the boundary, stated from your side too |

**Hand over the evidence, not the conclusion.** "Keepalive fixed the flapping"
is unverifiable. *"7 disconnects in 64s with no user action; after
`chrome.alarms periodInMinutes: 0.4`, 0 in 45s"* is something they can re-run
and disagree with.

### 3. Actually stop

Not "mostly stop". No opportunistic one-line fix, no "while I was there". If
you spot something, *tell them*; do not fix it.

The one exception worth stating aloud: if you find something **unsafe** on the
surface after handing it over, say so immediately and let them act. Silence to
avoid looking like you are meddling is worse than the interruption.

## Then peek, do not poll

Observation is [[herdr-peek]] — read-only, sends nothing, safe against an agent
mid-task:

```bash
/herdr-peek right
```

Read the **occupancy line** as well as the scrollback. `[working]` with a
background terminal running means subagents are live; `[blocked]` means it is
waiting on a human and your peek will not unblock it.

**Watch the context percentage.** Measured 2026-09-19: the receiving agent was
at `Context 31% left · 67.9M in` when it took ownership. On a long-running
session that is the constraint most likely to end the work — more likely than
the technical problem being handed over. Worth flagging to the human early,
because nobody else is looking at it.

Do **not** set a tight monitor loop on a peer. If you want notification rather
than sampling, watch their transcript for new turns instead of scraping the
pane — see [[herdr-peek]] for why the pane truncates and the JSONL does not.

## Sampling lies — count events, not samples

The single most expensive lesson behind this skill.

A status endpoint polled every 8s reported `connected` on all 8 polls while the
server log recorded **7 disconnects in the same window**. The fault healed faster
than the sample interval, so every sample landed on a healthy moment.

Applies directly to watching a peer: "I peeked three times and it looked fine"
is not evidence it was fine between peeks. When the question is *did this flap*,
count events at the source — server log lines, transcript turns, commit count —
never your own observations.

## If they hand it back

Re-measure before touching. Their edits, restarts and kills are invisible to you,
and your mental model of the surface is as old as the moment you let go of it.

## Anti-patterns

- Handing over without saying what is uncommitted → they discard your work, or
  build on it believing it is committed
- "I'll just fix this one thing first" → the overlap you were preventing
- Conclusions without measurements → they cannot verify, so they either trust
  blindly or redo it
- Polling a peer every few seconds → their pane is not a dashboard, and you will
  still miss anything shorter than your interval
- Staying silent about something unsafe because it is now their surface

## Related

[[herdr-peek]] observe · [[herdr-hey]] message · [[herdr-neighbors]] survey who
is around before assuming a pane is free · [[forward]] session-to-session, not
peer-to-peer
