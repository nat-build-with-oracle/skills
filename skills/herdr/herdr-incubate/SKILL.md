---
name: herdr-incubate
description: Work on ANOTHER oracle's topic from inside the CURRENT repo — validates the target through `maw locate`, then cuts a worktree of the current repo at <repo>/wt/<owner>-<target>-<date>, opens it as its own herdr space, and drops a .claude/INCUBATED_BY breadcrumb. Self-contained; works without any justfile recipe. Use when the user says "incubate <oracle>", "work on <oracle> from here", "build something for <oracle>", or points at a sidebar of nested oracle worktrees and asks for another. Do NOT use to open the target oracle's own repo (use /herdr-bring), to cut a worktree for a plain topic with no oracle behind it (use /herdr-wt), or to clone a third-party repo for development (use /incubate).
argument-hint: "<oracle> [dated|plain] [base-ref]"
---

# /herdr-incubate — another oracle's topic, in your own repo

The worktree is a branch of the **current** repo. It is NOT a checkout of the target.
`<oracle>-haos-14sep-mon2026` is <oracle>-oracle code, on a <oracle>-oracle branch, for haos work.

## Run it

```bash
TARGET=haos; BASE=HEAD; MODE=dated   # dated | plain

info=$(maw locate "$TARGET" --json 2>/dev/null) || true   # exits 1 on ambiguous, still prints JSON
test -n "$info" || { echo "REFUSING: maw locate $TARGET returned nothing"; exit 1; }
if echo "$info" | python3 -c "import json,sys; sys.exit(0 if 'candidates' in json.load(sys.stdin) else 1)"; then
  echo "AMBIGUOUS — re-run with an exact oracle name"; exit 1
fi
target_repo=$(echo "$info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('repoPath',''))")
test -n "$target_repo" || { echo "REFUSING: $TARGET has no repoPath"; exit 1; }

repo=$(git rev-parse --show-toplevel)
owner=$(basename "$repo" | sed 's/-oracle$//')
case "$MODE" in
  dated) name="$owner-$TARGET-$(TZ='Asia/Bangkok' date +%-d%b-%a%Y | tr '[:upper:]' '[:lower:]')" ;;
  plain) name="$owner-$TARGET" ;;
  *)     echo "REFUSING: MODE must be dated or plain"; exit 1 ;;
esac
dest="$repo/wt/$name"
test ! -e "$dest" || { echo "REFUSING: already exists: $dest"; exit 1; }

herdr worktree create --cwd "$repo" --branch "$name" --base "$BASE" --path "$dest" --no-focus \
  | python3 -c "import json,sys; print('space', json.load(sys.stdin)['result']['workspace']['workspace_id'])"
git -C "$repo" worktree lock --reason "herdr|$(whoami)@$(hostname -s)|$(date -Iseconds)|incubate $TARGET" "$dest"

mkdir -p "$dest/.claude"
printf 'oracle: %s\noracle-repo: %s\ndate: %s\nmode: herdr-incubate\ntarget: %s\ntarget-repo: %s\n' \
  "$owner" "$repo" "$(date +%Y-%m-%d)" "$TARGET" "$target_repo" > "$dest/.claude/INCUBATED_BY"
echo "$dest"
```

Then put an agent in it — the pane comes up as a bare shell:

```bash
herdr agent start <name> --kind claude --pane <pane>
```

**In `<org>/<oracle>-oracle` only**, wrapped as `just herdr-incubate <oracle> [base]`.

## dated vs plain

| MODE | name | when |
|---|---|---|
| `dated` (default) | `neo-haos-14sep-mon2026` | a task for that oracle; repeatable, and every `neo-haos-*` groups together |
| `plain` | `neo-haos` | a standing relationship where the oracle IS the identity, not the day |

`plain` is **one per target, forever** — the name carries no date to distinguish a second
one, so a future run refuses until you delete the branch. That is the point (it keeps a
long-lived body single) and also the cost (no second body without a rename). Pick `dated`
if you might ever want two at once.

Date-last exists for `dated` because maw writes single-digit days unpadded, so date-FIRST
does not sort chronologically (`9sep` after `10sep`). `plain` sidesteps the question.

## Why validate through `maw locate` at all

The branch is named after another oracle, so the name is a claim. `maw locate` is what
makes it true — it refuses an unknown name and refuses an ambiguous one instead of
minting `neo-typo-14sep-mon2026`. It also yields `repoPath`, which is the only thing
worth recording about the target, since the worktree does not contain it.

Two exit-code traps, both hit for real:

- `maw locate` **exits 1 on an ambiguous match while still printing valid JSON** with a
  `candidates` list. Under `set -e` that kills the script before you can read it. Always
  `|| true`, then test for `candidates`.
- Never pipe the check through `head` — the exit code becomes head's (0) and the guard
  silently passes.

## The breadcrumb

`.claude/INCUBATED_BY` is read by `/recap`, which prints an `⚠️ INCUBATED REPO` banner
from it. Same key order as the existing fleet convention (see
`<org>/oracle-status-tray/.claude/INCUBATED_BY`), plus `target` / `target-repo`.

Without it, the branch name is the only clue about intent, and it is gone the moment the
sidebar truncates.

## Which verb do I want

| Situation | Verb |
|---|---|
| Go work inside haos-oracle itself | `/herdr-bring haos` |
| Build something for haos, from <oracle>-oracle | `/herdr-incubate haos` |
| A topic with no oracle behind it | `/herdr-wt <slug>` |
| A third-party repo you must clone first | `/incubate <url>` |

`/incubate` is the different one: it clones into the ghq root and places bodies OUTSIDE
the repo, because a linked worktree's `.git` is a *file* and `ghq list` would report it
as a phantom repo. Ours sit inside an already-registered oracle repo, gitignored, so
nothing enumerates them. Do not "unify" the two layouts — see `/herdr-wt` for the full
argument.

## Cleanup

Unlock first; the lock blocks removal on purpose.

```bash
git -C <repo> worktree unlock wt/<name>
herdr worktree remove --workspace <wsid> --force
git -C <repo> worktree prune
git -C <repo> branch -D <name>          # only if it carries no commits you want
```

Check before removing:

```bash
git -C wt/<name> status --short                  # dirty?
git -C wt/<name> rev-list --count main..HEAD     # unmerged commits?
```

## Trap: someone else may already hold that name

The guard is `test ! -e "$dest"`, which refuses an existing path — but a refusal is
information, not just an error. On 2026-09-14 `neo-haos-14sep-mon2026` already existed,
cut by another agent an hour earlier. Read the existing worktree before assuming the name
is yours to reuse; `git log` and the lock reason say who and why.

## Related

- `/herdr-wt` — the naming convention and its evidence; the worktree traps apply here too
- `/herdr-bring` — land an oracle's own repo as a space (project skill in <oracle>-oracle)
- `/incubate` — clone a third-party repo for development
