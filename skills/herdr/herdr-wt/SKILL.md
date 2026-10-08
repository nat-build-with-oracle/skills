---
name: herdr-wt
description: Create a git worktree for a distinct piece of work in ANY repo, placed at <repo>/wt/<slug>-<oracle>-<date> and opened as its own herdr space (or, with --here, as a split pane in the current tab). By default it first checks the current repo and opens a GitHub issue carrying the FULL task context, then cuts the worktree, starts an agent and briefs it from that issue. Self-contained — works without any justfile recipe. Use when starting work that deserves its own branch and checkout, a parallel agent's workspace, or when the user says "make a worktree", "start work on X", "spin up a branch for this", "new wt dir". Also the reference for WHY the naming is slug-oracle-date and what breaks if that changes. Do NOT use to move an existing session into herdr (use /herdr-bring), to fork a session in place (`herdr` skill covers forking), or to spawn an isolated OMX/Codex worker (use /isolate-worktree).
argument-hint: "<slug> [base-ref] [--here] [--no-issue] [--repo [org]] | --list"
---

# /herdr-wt — worktree per piece of work

Works in any repo on any machine. Requires `herdr` on PATH and a git repo; nothing else.

## `--list` — what already exists

`herdr worktree list` is the only surface that shows **closed** worktrees. The sidebar
draws open spaces only, so a worktree you closed is invisible there while still being on
disk, still registered in git, and one `herdr worktree open --path <path>` from returning.
`open_workspace_id` is present when a space is open and absent when it is closed — that
field, not the sidebar, is the state.

```bash
herdr worktree list | jq -r '.result.worktrees[]
  | [ (if .open_workspace_id then "OPEN " + .open_workspace_id else "closed" end),
      (if .is_prunable then "PRUNABLE" else "-" end),
      .branch,
      (.path | sub("^" + (env.PWD | sub("/wt/.*$";"")); "·") | sub("^/Users/[^/]+";"~")) ]
  | @tsv' \
  | sort | awk -F'\t' '{printf "%-10s %-9s %-46s %s\n",$1,$2,$3,$4}'
```

Scoped to ONE repo — the response's `source` block shows which repo it resolved from the
cwd. It will not show another oracle's worktrees; for fleet-wide use `wt-picker ls`.

`is_prunable` is the column that matters: it flags a worktree `git worktree prune` would
drop. Locked ones read `false`, which is the whole point of the lock below.

## The flow (Nat, 2026-09-28)

`/herdr-wt <slug>` runs these five steps in order. Steps 1 and 5 are the ones people skip.

1. **Issue first** — check the current repo, open a GitHub issue that carries the full
   context of the task (section below). `--no-issue` skips it; so does a repo where you may
   not open issues.
2. **Worktree** — *Run it* below, with the issue number in the lock reason. New work goes
   in `ψ/lab/<slug>/` inside it (the default). `--repo [org]` makes a new repo instead;
   see *`--repo`* below.
3. **Record the workspace on the issue** — one comment: branch, path, herdr space and pane.
4. **Agent** — warm direnv, `pane run "claude"`, rename (see *Then put an agent in it*).
5. **Brief from the issue** — send the agent a short prompt that points at the issue.
   The issue is the brief; the prompt only says where it is and how to report back.

Why an issue and not just a long prompt: a prompt typed into a pane lives in that agent's
scrollback and dies with it. Nobody else can read it, review it, or find it next week. An
issue is durable, linkable, and readable by the human, the main session and any other
agent, and the eventual PR closes it with `Closes #N`. On 2026-09-28 two worktree agents
(presentation, proof-with-coding) were each briefed with ~60-line prompts that existed only
in their panes; this step exists so the next brief is not lost the same way.

## Step 1 — open the issue in the current repo

Check before opening anything:

```bash
gh repo view --json nameWithOwner,hasIssuesEnabled,viewerPermission \
  -q '"\(.nameWithOwner) issues=\(.hasIssuesEnabled) perm=\(.viewerPermission)"'
```

Open the issue only when all three hold:

- the cwd is a GitHub repo (`gh repo view` succeeds),
- `hasIssuesEnabled` is `true`,
- `viewerPermission` is `ADMIN`, `MAINTAIN` or `WRITE` — i.e. a repo we own or are a member
  of. **Never open issues on a third-party repo** (fleet rule: fix locally, document as
  knowledge). For those, say so and fall back to `--no-issue`.

The body must stand alone: an agent that reads only the issue should be able to do the work.
Write it for a reader who has never seen the conversation.

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
LABEL=$(gh label list --limit 100 --json name -q '.[].name' | rg -m1 '^oracle:' || true)
ISSUE_URL=$(gh issue create --repo "$REPO" --title "<slug>: <one-line goal>" \
  ${LABEL:+--label "$LABEL"} --body-file - <<'EOF'
## Goal
<what done looks like, one paragraph>

## Context
<why this exists; decisions already made; what was tried; links to prior issues/PRs/files>

## Sources
- <repo paths the agent must read first, with line ranges where useful>

## Deliverables
1. <file / artifact / PR>

## Rules
- <hard constraints: data it must not use, things it must not claim, no push/merge, etc.>

## Done when
- [ ] <checkable criterion>

## Out of scope
- <what not to touch>

## Workspace
Filled in by a comment once the worktree exists.

---
Opened by <oracle> (AI) via /herdr-wt · session <session-id>
EOF
)
ISSUE=${ISSUE_URL##*/}; echo "$ISSUE_URL"
```

Keep the `--body-file -` heredoc form: long bodies with backticks and `$` survive it intact,
where `--body "..."` gets mangled by the shell. The trailing attribution line matters because
the issue is authored by the human's GitHub account, not by the agent.

Then run *Run it* below with `ISSUE` set, and afterwards record the workspace:

```bash
gh issue comment "$ISSUE" --repo "$REPO" --body "Workspace
- branch: \`$name\`
- path: \`wt/$name\`
- herdr space: \`$SPACE\` · pane: \`$PANE\`
- agent: \`$SLUG-$owner\`
- lab: \`${lab:-none (no ψ/ in this repo)}\`"
```

## Run it

Copy-paste, substituting the slug (and optionally a base ref). With an issue, add `|#$ISSUE`
to the lock reason so the worktree can be traced back to it even after the space is closed:

```bash
SLUG=herdr-bring; BASE=HEAD
repo=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")   # MAIN checkout, see below
day=$(TZ='Asia/Bangkok' date +%-d%b-%a%Y | tr '[:upper:]' '[:lower:]')
owner=$(basename "$repo" | sed 's/-oracle$//')
name="$SLUG-$owner${ISSUE:+-issue$ISSUE}-$day"   # register-free-cloud-homelab-issue23-28sep-mon2026
dest="$repo/wt/$name"
test ! -e "$dest" || { echo "already exists: $dest"; exit 1; }
herdr worktree create --cwd "$repo" --branch "$name" --base "$BASE" --path "$dest" --no-focus \
  | python3 -c "import json,sys; print('space', json.load(sys.stdin)['result']['workspace']['workspace_id'], '->', sys.argv[1])" "$name"
git -C "$repo" worktree lock --reason "herdr|$(whoami)@$(hostname -s)|$(date -Iseconds)|$SLUG${ISSUE:+|#$ISSUE}" "$dest"
[ -f "$dest/.envrc" ] || [ ! -f "$repo/.envrc" ] || cp -a "$repo/.envrc" "$dest/.envrc"   # untracked: not in a new worktree
(cd "$dest" && maw token use "$(maw token resolve)")   # see below — token AND direnv trust, in one step
lab=""                                  # lab folder: only in repos with a ψ/ vault
if [ -d "$dest/ψ" ]; then
  lab="ψ/lab/$SLUG"
  mkdir -p "$dest/$lab"
  if git -C "$dest" check-ignore -q "$lab/x"; then
    printf '!%s/\n' "$lab" >> "$dest/.gitignore"
    git -C "$dest" check-ignore -q "$lab/x" \
      && { echo "$lab still ignored: a parent dir is excluded, fix .gitignore by hand"; exit 1; }
  fi
fi
echo "$dest"
```

**`repo` is the main checkout, from `--git-common-dir`, never `--show-toplevel`.** From
inside a worktree, `--show-toplevel` returns that worktree, so two things break at once:
`dest` nests as `<repo>/wt/<a>/wt/<b>` (the JSONDecodeError of 2026-09-15: `herdr worktree
create` answered with empty stdout), and `owner` becomes the worktree's folder name.
Measured 2026-10-08 from a herdr worktree: `--show-toplevel` gave owner
`worktree-calm-meadow-eea9`, `--git-common-dir` gave `neo`. The `just herdr-wt` recipe has
had this fix since 2026-09-15; this block lagged it until 2026-10-08.

**New work goes in `ψ/lab/<slug>/`** (Nat, 2026-09-28), the default when there is no
`--repo`. Oracle repos gitignore `ψ/` and re-include lab folders one by one
(`!ψ/lab/codex-fleet/` in homelab), so the block appends the same line for the new folder
and stops if git still ignores it. That `.gitignore` line is committed on the branch with
the work. Repos without `ψ/` skip this and work at the worktree root.

The lock is borrowed from `/incubate` (same `tool|who|when|why` field order, so one parser
reads both). It is **not** security — it is a "do not auto-clean me" flag, and it earns its
keep twice, both verified 2026-09-14:

- `git worktree prune` leaves it registered **even after the directory is deleted**.
  Without a lock, prune is exactly what silently drops a worktree — and prune is the
  command recovery docs tell people to run.
- `git worktree remove --force` refuses it outright:
  `fatal: cannot remove a locked working tree` (needs `-f -f`).

The lock reason is also the only per-worktree metadata that survives `kill -9`; it lives at
`<repo>/.git/worktrees/<id>/locked`, where `<id>` is the folder name at creation time
(a later `git worktree move` keeps it). `git -C <worktree> rev-parse --git-dir` prints it.

Produces, for slug `herdr-bring` in `<oracle>-oracle` on 14 Sep 2026:

| | |
|---|---|
| branch | `herdr-bring-neo-14sep-mon2026` |
| path | `<repo>/wt/herdr-bring-neo-14sep-mon2026` |
| herdr | its own space, `--no-focus` |

**In `<org>/<oracle>-oracle` only**, the same thing is wrapped as `just herdr-wt <slug> [base]`.
No other repo has that recipe — verified across the full `ghq list`, 1 of N repos — so
use the inline block everywhere else.

Then put an agent in it (the pane comes up as a bare shell):

```bash
herdr pane run <pane> 'echo "TOK=$CLAUDE_TOKEN_NAME"'   # warm direnv FIRST — see below
herdr pane run <pane> "claude"          # NOT `herdr agent start` — see below
herdr agent rename <pane> "$SLUG-$owner"   # agent names cap at 32 chars
```

That first throwaway command is not decoration — without it the agent can still come up
on the wrong token even though you used `pane run`. See *Trap: `pane run` is not enough on
a fresh worktree* below.

`herdr agent rename` run immediately after `pane run "claude"` can fail with
`{"error":{"code":"agent_not_found",...}}` — the claude process has not registered as an
agent yet (measured 2026-09-28, `<pane>`). Wait for it, then rename:

```bash
herdr pane wait-output <pane> --match 'bypass permissions' --timeout 40000   # MILLISECONDS
herdr agent rename <pane> "$SLUG-$owner"
```

`--timeout` is in **milliseconds**. The earlier `--timeout 40` meant 40 ms and timed out
every time, even with claude already up (measured 2026-09-28, `<pane>` and `<pane>`; the
same match returned instantly once the value was right).

### Brief the agent from the issue (step 5)

Send it through fleet (`fleet_send`, target = the pane id), not `herdr agent prompt`, which
prefix-matches agent names. Keep the prompt short; the issue carries everything:

```
Your task is GitHub issue #<N> in <owner/repo>: <issue URL>
Read it first: gh issue view <N> --repo <owner/repo> --comments
It is your full brief — sources, deliverables, rules, done criteria.
Report progress as comments on that issue (what is done, what is blocked, open questions).
Work only in this worktree, commit on this branch. Open a PR with "Closes #<N>" only if the issue says to.
```

Anything you learn later that changes the task goes on the issue as a comment first, then
into the pane with a one-line "see the new comment on #N". The pane is never the only copy.

**Do not use `herdr agent start` here**, despite it being the obvious command. Two
measured reasons, both 2026-09-17 in `mycelium-oracle`:

- **It bypasses direnv.** `herdr agent start` spawns claude from the *herdr server's*
  environment, not through the pane's shell, so the `.envrc` you just allowed never
  runs. The agent inherits whatever token the server happens to hold. Measured in
  `wt/mycelium-vm-server-17sep-thu2026`, where the repo is assigned `dd2`:

  | how the agent was started | `CLAUDE_TOKEN_NAME` in its process |
  |---|---|
  | `herdr agent start --kind claude` | `pb` ✗ |
  | `herdr pane run <pane> "claude"` | `dd2` ✓ |

  `herdr pane run` goes through the shell, direnv fires, the right token is inherited.
- **Its `<name>` argument caps at 32 characters** and the full worktree name often
  exceeds it — `mycelium-reincarnate-17sep-thu2026` is 34:

  ```
  {"error":{"code":"invalid_agent_name","message":"agent name must start with a
  lowercase letter and contain only lowercase letters, digits, '-' or '_' (1-32
  characters)"}}
  ```

  It **starts the agent anyway and leaves it unnamed** — the error lands after the
  side effect. Name the agent `<slug>-<owner>`; the workspace label already carries
  the full `<slug>-<owner>-<date>`.

## `--here` — new worktree, opened as a split in THIS tab (Nat, 2026-10-08)

Use it when the human wants a second parallel agent beside them, in the same pane layout,
but **not** in the same checkout. Two agents in one worktree share the branch and the git
index, so one `git add` stages the other's half-done edits. `--here` gives the second
agent its own branch and folder while the pane sits next to yours.

Everything else in the flow is unchanged: issue first, lock, `.envrc`, token, agent, and
brief. Only *Run it* changes, in two ways:

1. **`git worktree add`, not `herdr worktree create`.** The herdr command always opens a
   new space and has no flag to skip that.
2. **`pane split --cwd <dest>`**, so the new pane starts in the new worktree inside the
   current tab.

```bash
SLUG=<slug>; BASE=HEAD
main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")   # the MAIN checkout
day=$(TZ='Asia/Bangkok' date +%-d%b-%a%Y | tr '[:upper:]' '[:lower:]')
owner=$(basename "$main" | sed 's/-oracle$//')
name="$SLUG-$owner${ISSUE:+-issue$ISSUE}-$day"
dest="$main/wt/$name"
test ! -e "$dest" || { echo "already exists: $dest"; exit 1; }
git -C "$main" worktree add -b "$name" "$dest" "$BASE"
git -C "$main" worktree lock --reason "herdr|$(whoami)@$(hostname -s)|$(date -Iseconds)|$SLUG${ISSUE:+|#$ISSUE}" "$dest"
[ -f "$dest/.envrc" ] || [ ! -f "$main/.envrc" ] || cp -a "$main/.envrc" "$dest/.envrc"
(cd "$dest" && maw token use "$(maw token resolve)")
DIR=right   # use DIR=down when the tab already has two panes
PANE=$(herdr pane split --current --direction "$DIR" --ratio 0.5 --cwd "$dest" --no-focus \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['pane']['pane_id'])")
herdr pane rename "$PANE" "$name" >/dev/null
echo "$PANE -> $dest"
```

Then run the lab-folder block from *Run it* against `$dest`, and continue with *Then put an
agent in it* using `$PANE`. Use `--direction down` when the tab already has two panes.

- **Use `--git-common-dir`, not `--show-toplevel`.** From inside a worktree, the toplevel is
  that worktree, so `$toplevel/wt/...` would nest the new worktree inside the current one.
  Herdr's own spaces live in `~/.herdr/worktrees/<repo>/…`, where this matters every time.
- **The sidebar shows no new row.** The pane belongs to the current space, whose row
  still shows the current branch. Check the new branch with the pane's prompt,
  `herdr pane get $PANE` (`cwd`), or `git -C "$main" worktree list`.
- **Splitting a pane is not `--here`.** Right-click → split, or `pane split` without
  `--cwd`, opens the SAME worktree. A fresh `claude` there is a separate session, but it
  shares the files.

Tested 2026-10-08 on a scratch repo: `<pane>` opened in tab `<tab>` with cwd
`.../wt/demo-here-8oct-thu2026`, and the prompt showed the new branch.

### `--here` with no slug: the agent names it, then a popup (Nat, 2026-10-08)

The same act-then-veto flow as `/herdr-rename`. Do not open with a question.

1. **Pick the slug yourself.** Base it on what the human just said they want the new
   pane for, then on the conversation. Draft 3 slugs, best first: meaningful and
   memorable (`kong-cutover`, `fts-stopword-purge`), accurate before clever. Run the
   collision check on all three.
2. **Cut the worktree with the best pick right away.** From the `--here` block above,
   run only the lines up to and including `git worktree add` (setting `SLUG`, `main`,
   `day`, `owner`, `name`, `dest`, then the `test ! -e` check). Stop before
   `git worktree lock`.
3. **Popup, once.** AskUserQuestion: `Created <name>. Keep it?`. Option 1 is
   `Keep <slug> (Recommended)`, options 2-3 are the runner-ups with a one-line reason
   each, and the built-in Other takes a typed name.
4. **If the human picks another name, move the whole thing, not just the branch.** No
   agent and no pane exist yet, so the folder can still move safely:

   ```bash
   SLUG=<chosen-slug>; new="$SLUG-$owner${ISSUE:+-issue$ISSUE}-$day"
   git -C "$main" branch -m "$name" "$new"
   git -C "$main" worktree move "$dest" "$main/wt/$new"
   name=$new; dest="$main/wt/$new"
   ```

   Set `SLUG` to the final pick too. The lock reason in step 5 is built from `$SLUG`;
   on 2026-10-08 a test run kept the first pick there and had to re-lock.

   Tested 2026-10-08 on a scratch repo: `rc=0`, and `git worktree list` showed the new
   folder on the new branch.
5. **Then the rest of the `--here` block, from `git worktree lock` on,** with the FINAL
   slug: lock, `.envrc`, token, `pane split --cwd`,
   label. Lock **after** the popup, because `git worktree move` refuses a locked worktree.

   `git worktree move` keeps the admin dir under its FIRST name: after moving
   `here-demo-…` to `here-flow-trial-…`, the lock file was still
   `.git/worktrees/here-demo-here-test-8oct-thu2026/locked`. Find it with
   `cat "$(git -C "$dest" rev-parse --git-dir)/locked"`, never by building the path from
   the final name. Measured 2026-10-08, git 2.54.

Name, folder, branch, label and lock reason all agree, because nothing was created
under the old name except the folder you just moved.

**No evidence at all** (the human said nothing about the task): fall back to a herdr-style
placeholder and skip the popup, since there is nothing to choose between:

```bash
SLUG=$(printf '%s-%s-%s' "$(shuf -n1 -e amber brisk calm quiet silver)" \
  "$(shuf -n1 -e dune fern meadow river valley)" "$(openssl rand -hex 2)")   # e.g. quiet-dune-8846
```

- **Skip the issue** for a placeholder (implied `--no-issue`). An issue needs a goal.
  With an AI-picked slug, open the issue after the popup, under the final name.
- **Name a placeholder later with `/herdr-rename` in the NEW pane**, not in yours. It
  renames `git branch --show-current` of the pane it runs in, so running it from the
  original pane renames the wrong branch.

What a later rename changes and what it leaves behind. Measured 2026-10-08 on a scratch
repo, git 2.54:

| thing | after `git branch -m` |
|---|---|
| branch (prompt, `git worktree list`) | new name, rc=0 |
| commits, lock state | kept |
| folder `wt/<placeholder>…` | **unchanged** (moving it kills the agent's cwd) |
| lock reason | **unchanged**, still names the placeholder slug |
| pane label | follows: `/herdr-rename` step 3 renames it when it equals the old branch (tested, `<pane>`) |

`git branch -m` also works from a different worktree of the same repo (tested: renamed
from the main checkout, and the other worktree's prompt followed). Git updates every
worktree's HEAD.

## `--repo [org]` — a new repo instead of a lab folder

Without `--repo`, work lands in `ψ/lab/<slug>/` inside the worktree. With it, the work
gets its own repo. Everything else is the normal flow: issue here, worktree under
`<repo>/wt/`, agent, brief. **The main session does not run `/incubate`** (Nat,
2026-09-28); the agent in the worktree does, because the issue tells it to. The issue opens
in the current repo, because the new repo's name needs the issue number first.

Reuse check, in the main session:

```bash
oracle=homekeeper   # the oracle's own name (CLAUDE.md "I am"), not the repo folder (homelab)
[ -n "$ORG" ] || ORG=$(maw locate "$oracle" --json 2>/dev/null | jq -er .org) \
  || { echo "oracle '$oracle' not in the maw registry: pass --repo <org>"; exit 1; }
names=$(gh repo list "$ORG" --limit 1000 --json name -q '.[].name')
echo "$names" | rg "^$oracle-$SLUG-issue[0-9]+$"   # exact hit: reuse that repo
echo "$names" | rg -F -- "$SLUG"                   # loose hits: older names; show them, the human picks
```

- **Exact hit**: the agent will run `/incubate $ORG/<that-name>`. The old name keeps its old
  issue number, which is when the repo was born. A new issue is still opened (every piece
  of work gets its own brief) and links to the repo.
- **Loose hits only**: list them and ask. Do not pick for the human.
- **No hit**: the agent will run `/incubate $ORG/$oracle-$SLUG-issue$ISSUE`.
  `/incubate` creates the private repo when it does not exist and clones it with `ghq`.

Put that exact `/incubate` command in the issue as the first deliverable, with "add this
issue's URL to the new repo's README" as the second. Then do *Run it* exactly as usual,
minus the lab block (set `lab=""`, skip the `if`). The worktree sits under the current repo
with the others, and `/incubate` run from it links the clone under the worktree's
`ψ/incubate/`.

Do **not** open a bare space on the main checkout with `herdr workspace create --cwd "$repo"`.
Tried 2026-09-28 (space `w6Q`, closed): it lands in the sidebar as a separate `main` entry,
not in the repo's worktree tree, and its agent works in the main checkout.

The agent's name is `$SLUG-$owner`, or just `$SLUG` when that is over 32 characters
(`local-black-white-machine-homelab` is 33).

Check GitHub, not `ghq list`: ghq keeps stale entries. On 2026-09-28
`<org>/homekeeper-oracle` was in ghq and in the maw registry but not on GitHub; the
folder is an old clone of `<org>/homelab`. `maw locate` resolves oracles only
(`register-free-cloud` gives `not found in 313 registered`), so it supplies the org, not
the reuse answer.

## Before first use on a new machine — one prerequisite

`wt/` is already ignored **fleet-wide** via `~/.config/git/ignore` (added 2026-09-14).
Git reads that path by XDG default when `core.excludesFile` is unset, so no per-repo
`.gitignore` edit is needed — one line covers every repo on the machine. Verify on a new
machine before trusting it:

```bash
git check-ignore -v wt/x || printf '/wt/\n' >> ~/.config/git/ignore
```

The leading slash anchors it to each repo's root, so it does not shadow nested `wt/`
directories such as incubate's `ψ/incubate/<slug>/wt/`.

**`dig.py` must fold `wt`** or every worktree reports as its own phantom project in
`/dig`. Check and patch the global skill file:

```bash
rg -n 're\.sub' ~/.claude/skills/dig/scripts/dig.py | rg 'wt'
# want: re.sub(r'-(wt|agents)-.*$', '', base)
# NOT:  re.sub(r'-wt-\d+.*$', '', base)
```

The original required a **digit** right after `wt-`, so it matched `wt-1-white` but not
`wt-herdr-14sep-mon2026`. Session dirs then fall through to `clean.split('-')[-1]` and
report as a phantom repo — exactly why `homelab-agents-1-gpu` showed up as repo `gpu`.
Applied on m5 2026-09-14; **white still needs it**.

## Why the name is shaped this way

Decided against the obvious alternatives, with evidence. Do not "fix" them back without
re-running the same checks.

**Date goes LAST.** maw's own day repos are date-first, so date-first looks consistent.
Two reasons it isn't, for worktrees:

1. *Date-first does not sort chronologically.* maw writes single-digit days unpadded
   (`1sep-tue2026` … `9sep-tue2026`), so `9sep` sorts **after** `10sep`. Verify:
   `printf '%s\n' 9sep-tue2026-a 10sep-wed2026-b | sort`
2. *Trailing it groups by topic* — every `herdr-*` worktree lands together instead of
   scattering across months.

Not an inconsistency with maw: its date-first names are **day repos** where the date is
the identity. A worktree is **task-scoped** — the task is the identity, date is metadata.

**Slug FIRST, then the oracle** (changed 2026-09-20). The oracle still belongs in the
name — a branch, a PR and `git worktree list` are all flat, and there `herdr-14sep` alone
does not say whose it is. But it must not lead, because herdr's sidebar **groups by repo
now** and truncates from the right: under a `<oracle>-oracle` node every row began `neo-` and
the prefix spent ~4 of ~9 visible characters repeating what the parent already said.

Measured over 38 live workspaces, collisions *within a repo group* by visible width:

| chars | `<oracle>-<slug>-<date>` | `<slug>-<oracle>-<date>` |
|---|---|---|
| 9 | 5 | 2 |
| 14 | 3 | **0** |
| 18 | 1 | **0** |

The old order produced the exact ambiguity the prefix existed to prevent —
`neo-herdr…` for both `neo-herdr-14sep` and `neo-herdr-remote-16sep`, `neo-arra-…` for
both arra worktrees. Slug-first resolves every pair by 14 characters.

`<oracle>-oracle` → `<oracle>`; a non-oracle repo keeps its basename (`homelab` → `…-homelab-…`).

The earlier rationale said the sidebar "lists spaces FLAT". That was true on 2026-09-14
and is not true now; it is a three-level tree (Local → repo → worktrees). If it ever goes
flat again, the owner is still present, just later in the string.

**Issue number between oracle and date** (`-issue23-`, Nat 2026-09-28). The branch then
names its own brief: `register-free-cloud-homelab-issue23-28sep-mon2026` points at #23
without opening anything. Written `issue23`, not `i23`, so it reads without a legend.
No issue (`--no-issue`), no segment.

**A new repo (`--repo`) is `<oracle>-<slug>-issue<N>`**, with the oracle first and no date
(Nat, 2026-09-28): `homekeeper-register-free-cloud-issue23`. The GitHub org list and
`ghq list` are flat and alphabetical, with no parent node to group by, so the oracle prefix is
what keeps one oracle's repos together. A repo outlives the day it was made, so the date stays
on the worktree and branch, and the issue number already says where it came from. The
`-issue<N>` tail also ends the slug, so `^homekeeper-register-free-cloud-issue[0-9]+$` finds
that feature and never `register-free-cloud-api`. `--repo` therefore needs an issue; it does
not combine with `--no-issue`.

The first run (#25, 2026-09-28) used an earlier draft,
`<oracle>-<slug>-<oracle>-issue<N>-<day>` (69 characters). Nat dropped the repeated oracle and
the date the same day.

**Location `<repo>/wt/`, not `~/.herdr/worktrees/`.** herdr's `worktrees.directory` is a
single global root it appends `<repo>/<branch>` to — it cannot express "relative to the
current repo". `--path` is the only lever. `wt` also matches the convention already
dominant on disk (`homelab-wt-1-white`, `wt-2-cftunnel`, `wt-statusline`).

## Always `maw token use` the new worktree

A worktree is a **new path**, so direnv's allow-list has never seen it — even
though the parent repo is trusted and `.envrc` is the identical file. Until you
allow it, direnv refuses to load and every pane opened there starts **without**
the repo's environment.

`direnv allow "$dest"` fixes only half of that, so **call `maw token use` instead** —
it does both jobs in one step. Measured 2026-09-17 on
`wt/mycelium-vm-server-17sep-thu2026`:

| | rewrites `.envrc` to the assigned token | direnv-allows the new path |
|---|---|---|
| `direnv allow "$dest"` | no | yes |
| `maw token use <name>` | yes | yes |

Proof for both halves. Trust: with the allow-file deleted, `maw token use dd2`
recreated `~/.local/share/direnv/allow/dc56099d…` on its own. Token: `maw token use pb`
rewrote **both** lines of the worktree `.envrc` (the `CLAUDE_TOKEN_NAME` line and the
token-fetch command line), and
`maw token use dd2` restored it byte-for-byte.

Why the token half matters: the `.envrc` a worktree starts with is a **copy**, so it
names whatever token the source checkout named at copy time. `direnv allow` faithfully
trusts a stale answer. `maw token resolve` reads the assignment for the cwd's oracle —
it resolves correctly from inside a worktree, verified — so the repo-agnostic form is:

```bash
(cd "$dest" && maw token use "$(maw token resolve)")
```

Skipping this is not cosmetic. Agents in an unallowed worktree run without
the Claude Code login-token variable, `CLAUDE_TOKEN_NAME`, `ORACLE_URL` and `ORACLE_PROJECT` — a
different environment than the shell that created them, which surfaces later as an auth
failure nobody can reproduce. Measured 2026-09-15 on `wt/<slug>-<oracle>-14sep-mon2026`, the
pane showed:

```
direnv: error …/.envrc is blocked. Run `direnv allow` to approve its content
```

while the *loaded* RC was a different repo's entirely.

It is a trust decision, so read the file before approving it — `.envrc` here
shells out to a secret manager for a real token.

### Verify the process, not the statusline

```bash
direnv exec "$dest" bash -c 'echo "$CLAUDE_TOKEN_NAME $ORACLE_PROJECT"'
```

That proves what a *shell* at that path gets. It does **not** prove what a running
agent got — those differ whenever the agent was started outside the shell. The
statusline is no help either: its `🔐<name>` marker reads `.envrc`, so it happily
displayed `🔐dd2` for an agent whose process actually held `pb`. The only check that
settles it:

```bash
ps -Eww -p <agent-pid> | tr ' ' '\n' | rg '^CLAUDE_TOKEN_NAME'
```

Find the pid by cwd:

```bash
pgrep -f 'claude --dangerously' | while read p; do
  c=$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | rg '^n/' | sed 's/^n//' | head -1)
  [ "$c" = "$dest" ] && echo "$p"
done
```

Two details in that snippet are load-bearing, both measured 2026-09-21:

- **`pgrep -f claude` is too wide.** An agent's MCP servers inherit its cwd, so the plain
  pattern returned 5 pids all reporting the worktree directory — `uv`/`serena`, a
  `python`, a `bun` plugin server, and the real `claude`. They all carried the same
  (wrong) `CLAUDE_TOKEN_NAME`, so the output looked like corroboration rather than one
  fact repeated four times. Match the claude invocation, then confirm with
  `ps -o pid,lstart,command -p <pid>`.
- **`rg '^n'` must be `rg '^n/'` and end in `head -1`.** `lsof -Fn` emits other `n`-prefixed
  fields; without the anchor and the head, `$c` can pick up a non-path line and the
  comparison silently never matches.

Recovery is cheap when the agent is fresh: `herdr agent prompt <pane> '/exit'`, then
`herdr pane run <pane> "claude"`.

## Trap: `pane run` is not enough on a fresh worktree

The table above says `pane run` gets the right token. That holds only if the pane's shell
reached a **prompt after** `maw token use` allowed the path. On a worktree you just created
it usually has not, and the agent comes up on the server's token anyway.

Measured 2026-09-21, `wt/maw-cli-neo-21sep-mon2026` (repo assigned `dd2`):

| | |
|---|---|
| `.envrc` | `dd2` |
| statusline | `🔐dd2` |
| agent process | **`pb`** ✗ |

The sequence is the cause. `herdr worktree create` opens the space, and its pane shell
starts **immediately** — before `maw token use` runs. direnv evaluates once, at that
prompt, finds the path untrusted, and refuses. Allowing the path afterwards does not
reach back into a shell that is already sitting at a prompt, so `pane run "claude"`
executes in a shell holding no repo environment and claude inherits the herdr server's.

Fire one throwaway command first — any command, its output does not matter. It forces a
fresh prompt, direnv evaluates against the now-trusted path, and the shell picks the
token up:

```bash
herdr pane run <pane> 'echo "TOK=$CLAUDE_TOKEN_NAME"'
# expect in the pane: direnv: loading .../.envrc   then   TOK=<assigned>
herdr pane run <pane> "claude"
```

If you skip it and find the agent on the wrong token, recovery is the same as elsewhere:
`herdr agent prompt <pane> '/exit'`, one throwaway command, then `pane run "claude"`.

## Cleanup

Unlock first — the lock blocks removal on purpose:

```bash
git -C <repo> worktree unlock wt/<name>
herdr worktree remove --workspace <wsid> --force
```

Removes the checkout AND deregisters from `git worktree list` in one step. Check first:

```bash
git -C wt/<name> status --short                  # dirty?
git -C wt/<name> rev-list --count main..HEAD     # unmerged commits?
```

If the worktree was ever **moved**, herdr's record keeps the OLD path — it deletes the
space but leaves the real checkout behind. Finish with git:

```bash
git -C <repo> worktree remove wt/<name>
```

## Trap: never `git worktree move` a worktree with a live agent in it

A running agent pins its **cwd and Claude project dir at startup**. git and herdr both
relocate cleanly — git metadata updates, herdr's pane cwd follows — but the agent inside
cannot follow. It points at a vanished path and silently falls back to the main repo.

The tell is quiet: `pwd` inside the agent returns the **main repo**, and its status line
reads `main@<sha>` instead of the worktree branch.

A healthy worktree agent shows path, branch, and 🌳:

```
📁 <org>/<oracle>-oracle/wt/<slug>-<oracle>-14sep-mon2026
   <slug>-<oracle>-14sep-mon2026@31d3ceb 🌳
```

**Rule**: move while empty, or restart the agent after. Restart is cheap — `/exit` (two
`ctrl+c` did NOT exit it), then `herdr pane run <pane> "claude"` again; the pane cwd is
already right, and going through the shell is what re-applies direnv.

## Trap: worktree identity lives on the SPACE, not the pane

From herdr's source, `src/workspace.rs:196` — `worktree_space` is a field on `Workspace`.
`pane.rs` and `tab.rs` contain **zero** `worktree` references.

Moving a worktree's pane into another space's tab strips its worktree identity: it loses
the indented nesting and inherits the destination's branch label. `herdr worktree list`
then shows `open_workspace_id: -`. Recover:

```bash
herdr worktree open --cwd <repo> --path <worktree-path> --label <name> --no-focus
```

Adjacency and worktree identity are mutually exclusive — a model limit, not a missing flag.

**Putting worktree agents side by side and back (`/herdr-room`).** A room takes them OUT of their
worktree spaces, so the nesting disappears while they share a page. That is expected. On
`herdr-room out`, check that they nest again:

```bash
herdr workspace list | python3 -c "import json,sys; [print(w['workspace_id'], w.get('label'), 'WT' if w.get('worktree') else 'FLAT') for w in json.load(sys.stdin)['result']['workspaces']]"
```

Any `FLAT` row that should be a worktree is repaired in place, with no pane move and the agent
untouched, by the `worktree open` above (`already_open: true` means it attached to the existing
space). Measured 2026-10-06: herdr-room before its fix broke 5 worktree agents out flat. 4 were
repaired this way. The 5th was registered to its old space (kept alive by a helper pane), so it was moved back
there with `pane move --tab <old tab> --target-pane <pane> --split right`.

## Trap: don't branch in a shared checkout

`git checkout -b` in a repo other agents are working in moves **all of them** onto your
branch. That is what this skill exists to avoid — use a worktree for branch work,
including your own PR branches.

## Boundary with `/incubate --wt`

Both cut worktrees; they do not merge and neither calls the other. The split is
**ownership of the repo**, and it decides where the checkout may legally live.

| | `/incubate --wt` | `/herdr-wt` |
|---|---|---|
| repo | someone else's, cloned via `ghq` | an oracle repo you own |
| worktree path | `$XDG_STATE_HOME/incubate/worktrees` (outside) | `<repo>/wt/` (inside) |
| branch | `incubate/<slug>` | `<slug>-<oracle>[-issue<N>]-<date>` |
| lock | always, at creation | always, at creation (adopted from incubate) |
| opens a herdr space | no | yes |

**Why incubate must stay outside and we may stay inside** — from incubate's own notes:
`ghq list` decides "is this a repository" by `stat`-ing `<dir>/.git`, and a linked
worktree's `.git` is a *file*, not a directory. A worktree under the ghq root therefore
registers as a phantom repo. Incubate clones *into* the ghq root, so it has no choice but
to place bodies elsewhere. Our `wt/` sits inside an oracle repo that is already a single
ghq entry, and it is gitignored, so nothing enumerates it. Same constraint, two correct
answers — do not "unify" them onto one path.

**Picking one**: if you would open a herdr space for it, it is `/herdr-wt`. If it is a
third-party repo you are contributing to, it is `/incubate`.

## Boundary with `/herdr-ticket`

`/herdr-ticket` starts from an issue that **already exists** and cuts a
`wt/<oracle>-<slug>-<date>` branch off `origin/<default>`. `/herdr-wt` **creates** the issue
from the work you are about to start. If the issue exists, use `/herdr-ticket`; if it does
not, `/herdr-wt` writes it.

## Related

- `/herdr-bring` — land an existing maw handle into a herdr space (project skill in <oracle>-oracle)
- `herdr` (global skill) — the CLI reference: panes, agents, forking, prompting
- `/isolate-worktree` — different tool: spawns an isolated OMX/Codex worker
