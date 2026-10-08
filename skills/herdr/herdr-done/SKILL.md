---
name: herdr-done
description: Decide whether a herdr session can be closed — audits the pane's tree for work that would be lost (uncommitted changes, unpushed commits, no upstream, detached HEAD), then walks the hand-off steps that turn "clean" into "cleared". Use when the user says "done", "herdr done", "can I close this", "wrap up this pane", "is this session safe to kill", or before a reboot. Do NOT use to end the whole day across every worker (use /teardown), to write a retrospective (use /rrr), or to sign a PR on its own (use /herdr-pr).
---

# /herdr-done — is this session safe to close?

A pane closing is not the risk. Closing a pane whose work exists nowhere else is.

## Run it

```bash
# audit this pane
~/.claude/skills/herdr-done/herdr-done.sh

# audit another pane, by agent name or pane id
~/.claude/skills/herdr-done/herdr-done.sh mycelium-reincarnate

# a repo that is NOT this pane's cwd — an incubated checkout
~/.claude/skills/herdr-done/herdr-done.sh --work "$(ghq root)/github.com/<org>/<repo>"

# exit code only, for a script or a pre-reboot gate
~/.claude/skills/herdr-done/herdr-done.sh --quiet; echo $?
```

| exit | meaning |
|---|---|
| 0 | nothing would be lost |
| 1 | blockers — something would be |
| 2 | no herdr agent for that pane |

## clean ≠ cleared

Two different states, and only the first one is mechanical.

**clean** — nothing would be lost if the pane died right now. That is what the
script decides, and it is the only part a script *can* decide.

**cleared** — clean, plus the work has been handed off: signed, and the people
who need to know have been told. A pane can be perfectly clean and still leave a
PR that nobody knows to review, which is how work goes quiet without anyone
making a mistake.

So the full sequence is:

```
audit  →  blocked?  →  fix, re-audit
   ↓ clean
sign   →  /herdr-pr, posted on the PR this session produced
   ↓
notify →  the parent oracle, by whatever channel the fleet uses
   ↓
cleared
```

Steps 2 and 3 are deliberately **not** in the script. Signing needs the PR
number, and notifying sends a message to another human or oracle — both are
outward-facing, both deserve a person's judgment about wording and timing, and
neither should happen as a side effect of an audit someone ran to answer a
question.

## What it checks

**Blockers** — work that exists only in this pane:

| check | why it blocks |
|---|---|
| uncommitted changes to tracked files | the edits are in no commit |
| commits not pushed to the upstream | they live on one disk |
| a branch with no upstream, holding commits no remote has | nothing off this machine has ever seen them |
| detached HEAD | commits here are reachable from no branch once the reflog ages out |

**Warnings** — worth a look, but not loss:

| check | why it matters |
|---|---|
| untracked files | build junk, or work that was never `git add`ed — only you can tell |
| worktree dir name ≠ branch name | the next session reads the directory name and trusts it |
| worktree not locked | `git worktree prune` can remove it out from under live work |

**Notes** — context, never a verdict: how far behind the upstream is, the state
of the PR for this branch, whether the worktree is locked.

## Traps

1. **Session, not shell** — every path comes from the pane's cwd, never `$PWD`,
   for the same reason `/herdr-pr` does it: an audit of the directory your shell
   wandered into is an audit of nothing.

2. **Parse herdr's JSON with `\x1f`, not tab.** Bash collapses runs of whitespace
   IFS characters, so an agent with no name shifts every later field one column
   left — and the audit then reads a status as a cwd without complaining.

3. **Untracked files warn, they do not block.** Making them a blocker means every
   repo with a stray `.DS_Store` reports "blocked" forever, and a check that is
   always red is a check nobody reads.

4. **An open PR is a note, not a blocker.** Ending the day with a PR in review is
   normal. The script says so and lets you decide; a skill that refuses to let
   you close a pane over an open PR would be wrong more often than right.

5. **Read-only, on purpose.** It never commits, pushes, merges, unlocks, or kills
   a pane. Closing the pane is the irreversible half, and it stays with whoever
   read the report. An auditor that fixes things is an auditor you cannot run
   just to look.

6. **A clean audit is not a green light to `worktree remove`.** The branch may
   still be the only place the work lives. Retiring a body is `/incubate
   --offload`, which has its own guards.

## Don't use it for

The whole day across every worker (`/teardown`), a retrospective (`/rrr`), or
signing a PR by itself (`/herdr-pr`). This answers one question about one pane.
