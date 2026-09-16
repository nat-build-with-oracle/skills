---
name: herdr-pr
description: Sign a PR, issue, or comment with a "Built by" block — which oracle and model built it, from which worktree and branch, the session transcript holding the reasoning, and the herdr address a human or another agent can talk back to. Use when opening or commenting on a PR from a herdr pane, when the user says "sign your name", "sign the PR", "who built this", "how do I reach that session", or when several worktrees push to one repo and a reviewer needs to know which session produced the diff. Do NOT use to create a worktree (/herdr-wt), to move a session into herdr (/herdr-bring), or as a substitute for a real PR description.
argument-hint: "[pr-number]"
---

# /herdr-pr — sign a PR with a reachable address

A PR body says what changed. This says who to ask when it's wrong.

## CLI

```bash
# 1. name the agent — the name is the address (do this once)
herdr agent rename "$HERDR_PANE_ID" <name>

# 2. print the block (pass your OWN exact model id; the script can't read it)
~/.claude/skills/herdr-pr/herdr-sign.sh claude-opus-5

# 2b. PR in a repo that is NOT this pane's cwd — an incubated repo, a worker's
#     checkout: name it, or the block signs the oracle's branch on someone
#     else's PR
~/.claude/skills/herdr-pr/herdr-sign.sh claude-opus-5 --work "$(ghq root)/github.com/<org>/<repo>"

# 2c. taller block — one value per line, no quoting rules at all
~/.claude/skills/herdr-pr/herdr-sign.sh claude-opus-5 --work <path> --tall

# 2d. a commit the working tree is NOT on — a merged PR whose SHA the rebase
#     rewrote, or a second PR in the same repo
~/.claude/skills/herdr-pr/herdr-sign.sh claude-opus-5 --work <path> --ref <sha|branch>

# 3. post it
~/.claude/skills/herdr-pr/herdr-sign.sh claude-opus-5 --work <path> | gh pr comment <N> --body-file -

# 4. anyone reaches the session
herdr agent prompt <name> "question"    # ask; answers with full context
herdr agent read   <name>               # what it printed back
herdr agent focus  <name>               # jump a terminal there
```

Second arg signs another pane: `herdr-sign.sh gpt-5-codex w24:p5` — for a lead
signing a worker's PR.

## Agents

claude, omp (Oh My Pi) and codex all store transcripts differently. The script
handles all three; the encodings differ in ways that look like typos:

| agent | transcript | cwd key |
|---|---|---|
| claude | `~/.claude/projects/<key>/<uuid>.jsonl` | `/` **and** `.` → `-` |
| omp | `~/.omp/agent/sessions/<key>/<ts>_<uuid>.jsonl` | only `/` → `-`, wrapped in `--…--` |
| codex | `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl` | none — found by uuid |

herdr reports no session id for omp, so the newest transcript in the cwd's dir
wins and the id is read back off the filename. Only claude has a memory dir.

Repo wrapper, when it exists: `just herdr-sign <model-id>`.

## Why the name

| target | `herdr agent get` |
|---|---|
| pane id `w2F:p1` | works, but reassigned after a herdr restart |
| agent name | works once claimed, re-claimable |
| workspace label (what the sidebar shows) | `agent_not_found` |

Unnamed → the script signs a pane id and warns on stderr. A stale pane id points
reviewers at the wrong agent; that's worse than pointing nowhere.

## Traps

1. **Session, not shell** — paths come from the pane's cwd, never `$PWD`. Check: `cd /tmp && herdr-sign.sh x | head -8` must show the pane's repo.
2. **Memory keys off the MAIN checkout**, not the worktree.
3. **Parse herdr's JSON with `\x1f`, not tab** — bash collapses runs of whitespace IFS chars, so an agent with no name or no session id (every omp agent) shifts every later field one column left. That misfire is silent: the block still prints, with a cwd in the `session` line.

4. **`--work` is the PR's repo, not `$PWD`** — same discipline as trap 1, from
   the other side: pass the path explicitly, never let the shell's cwd decide.
5. **One checkout cannot be on two branches** — `--work` gets the repo right but
   still reads whichever branch is checked out, so signing PR B while working
   PR A silently cites A's branch and head. Use `--ref`; it never touches the
   tree, which matters when a server is running out of it.
6. **A rebase merge rewrites the SHA** — a signature posted before the merge
   cites a commit that only exists on the un-merged branch. Re-sign merged PRs
   with `--ref <landed-sha>` so the block names what is actually on main.
7. **A flag that only reaches one stanza is a no-op in the other** — `--ref`
   fed the `incubated:` pair, which is suppressed when the PR's repo *is* the
   session's checkout, so same-repo `--ref` validated the sha and then printed
   the tree's branch anyway. Traps 5 and 6 are both same-repo, so the flag did
   nothing in exactly the cases it exists for, and the block still looked
   right. Test every flag in both shapes: with `--work` and without.

After editing the script, `ls` both printed paths. A block whose paths 404 reads
authoritative and sends people nowhere.

## Two repos, two stanzas

An oracle working an **incubated** repo has its pane cwd in the vault and the
diff in `$(ghq root)/...`. The session facts and the code facts then come from
different checkouts, and the default block reports only the session's — so a
reviewer reads the oracle's branch and HEAD as if they were the PR's.

`--work <path>` adds a second stanza for the repo the PR is in, and picks up the
`.claude/INCUBATED_BY` breadcrumb `/incubate` leaves there (shown here in
`--tall` form, one value per line):

```yaml
agent:
  who: >-
    neo — <org>/<oracle>-oracle
  model: >-
    claude-opus-5
  runtime: >-
    claude

worktree:
  cwd: >-
    $(ghq root)/github.com/<org>/<oracle>-oracle/wt/<space>
  branch: >-
    <space>
  wt: >-
    worktree of $(ghq root)/github.com/<org>/<oracle>-oracle
  head: >-
    31d3ceb5 Merge pull request #31 …

incubated:          # only when --work names a different repo
  repo: >-
    <org>/idea-11sep-fri2026-cc-chat-ui
  branch: >-
    feat/server-side-repository-preferences
  head: >-
    97548ce feat: share repository preferences…
  work: >-
    $(ghq root)/github.com/<org>/<repo>
  link: >-
    …/ψ/incubate/<owner>/<repo>/origin
  by: >-
    neo on 2026-09-16

session:
  id: >-
    8f3ac9b3-…
  transcript: >-          # full block only
    …
  memory: >-              # full block only
    …

herdr:
  address: >-
    neo-digger
  pane: >-
    w2N:p1
  tab: >-
    w2N:t1
  space: >-
    neo-digger-16sep-wed2026
  title: >-
    Find this app v
  socket: >-              # full block only
    …
```

`--compact` folds every value back beside its key — 25 lines instead of 41 on a
four-group block, at the cost of re-quoting (see below):

```yaml
agent:
  who:        'neo — <org>/<oracle>-oracle'
  model:      'claude-opus-5'

worktree:
  cwd:        '$(ghq root)/github.com/<org>/<oracle>-oracle/wt/<space>'
  head:       '31d3ceb5 Merge pull request #31 from …'
```

Valid YAML either way, so a reviewer reads it and a script parses it:

```bash
gh api repos/<org>/<repo>/issues/comments/<id> --jq .body \
  | sed -n '/```yaml/,/```$/p' | sed '1d;$d' | yq -r '.herdr.address'
```

**Values are folded block scalars (`>-`) on their own line, never bare.** Inside
one, `#` starts no comment and `:` separates no key, so a git subject survives
verbatim. Bare, `head: 31d3ceb5 Merge pull request #31 from x` parses as
`31d3ceb5 Merge pull request` — silent truncation that still looks correct.
Omitted fields are absent keys, so `yq` returns `null` rather than an empty
string.

Compact — the default — is the one place those quoting rules come back: folding
the value onto the key line re-exposes `#` and `: `, so the transform
single-quotes every value and doubles any apostrophe inside it. Verified on
`it's a 'quoted' value`, on a `#31` subject, and on a `feat: …` subject. Reach
for `--tall` when a value is doing something stranger than those.

Four groups, in the order a reviewer asks: **who** built it, from **which tree**,
**which session** holds the reasoning, and **how to reach it** — plus a fifth,
`incubated`, naming **which repo** the diff is in, only when `--work` points at a
repo that is not the session's own checkout.

`work` is the ghq clone, `link` the vault symlink `/incubate` created — two ways
into the same checkout, and a reader on the fleet needs one of them to `cd`
there. A repo slug alone says which code to read, not where it is.

Both print in both blocks. `link` was public-omitted for one revision, on the
grounds that its path carries the private oracle repo name — but the public block
also prints the oracle `cwd` and its worktree parent, which carry the same name,
so withholding one path while printing two others bought nothing and only made
the rule hard to predict.

Merging the two into one `branch`/`head` pair is the bug this replaces: a lone
branch name gives the reader nothing to attach it to, so they assume it is the
PR's.

## Visibility decides how much leaks

The script reads `gh repo view <slug> --json isPrivate` for the **work** repo and
prints the redacted block unless the repo is proven private:

| repo | block |
|---|---|
| private | everything |
| public | everything except the agent's own storage: transcript, memory dir, herdr socket |
| unknown (gh failed) | same as public, with a stderr warning |

The line is **code vs. content**. Paths to code — oracle cwd, worktree, work
checkout, vault symlink — identify which tree produced the diff, and a reviewer
who can already read the repo gains nothing dangerous from them. Paths to
content — the transcript of everything this session reasoned about, the memory
dir, the socket that accepts commands — stay out of public view.

Treating unknown as public is deliberate: guessing wrong toward "private"
publishes the transcript path to the internet, and GitHub has mailed it out
before anyone notices. `--full` forces the complete block once you have checked.

Even redacted, the block still answers the question the signature exists for:
which oracle, which model, which commit, and an address that answers back.

## Don't sign

Commits (use `Co-Authored-By`), third-party repos you do not own, or PRs nobody
will review. Public repos you DO own are fine — they get the redacted block
automatically.
