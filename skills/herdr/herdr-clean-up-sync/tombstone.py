#!/usr/bin/env python3
"""tombstone: write the record of a worktree BEFORE it is removed (ดับไป != deleted).

A worktree ceases as an active thing; what it was, why it ended, who succeeds it and
where its record lives must survive it. Dry run unless --write. Never overwrites a
tombstone. Never removes anything.

  tombstone.py <worktree-path> [--reason TEXT] [--write]
"""
import json, subprocess, sys, os, glob, datetime

def run(cmd, cwd=None):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=15).stdout.strip()
    except Exception:
        return ""

def main():
    args = [a for a in sys.argv[1:]]
    write = "--write" in args
    reason = ""
    if "--reason" in args:
        i = args.index("--reason"); reason = args[i + 1]; del args[i:i + 2]
    args = [a for a in args if a != "--write"]
    if not args: print(__doc__); sys.exit(2)
    path = os.path.realpath(args[0])

    wts, cur = [], {}
    for line in run(["git", "-C", path, "worktree", "list", "--porcelain"]).split("\n"):
        if not line:
            if cur: wts.append(cur); cur = {}
            continue
        k, _, v = line.partition(" "); cur[k] = v or True
    if cur: wts.append(cur)
    me = next((w for w in wts if os.path.realpath(w["worktree"]) == path), None)
    if not me or me is wts[0]:
        print("refusing: not a linked worktree (a main checkout is never tombstoned)"); sys.exit(2)
    main_path, main_sha = wts[0]["worktree"], wts[0]["HEAD"]
    repo = os.path.basename(main_path)
    branch = (me.get("branch") or "").replace("refs/heads/", "") or "(detached)"
    head = me["HEAD"]
    now = datetime.datetime.now().astimezone()

    # herdr: label + agent sessions
    label, sessions = os.path.basename(path), []
    try:
        for w in json.loads(run(["herdr", "workspace", "list"]))["result"]["workspaces"]:
            if os.path.realpath((w.get("worktree") or {}).get("checkout_path", "")) == path:
                label = w.get("label", label); wid = w["workspace_id"]
                for p in json.loads(run(["herdr", "pane", "list"]))["result"]["panes"]:
                    if p.get("workspace_id") == wid and p.get("agent_session"):
                        sid = p["agent_session"]["value"]
                        tr = glob.glob(os.path.expanduser(f"~/.claude/projects*/*/{sid}.jsonl"))
                        sessions.append((p.get("agent"), sid, tr[0] if tr else "(transcript not found)"))
    except Exception:
        pass

    # born: oldest reflog entry of the branch; own commits since then
    rl = run(["git", "-C", path, "reflog", "show", "--date=iso", "--format=%H|%gd|%gs", branch if branch != "(detached)" else "HEAD"]).split("\n")
    born_sha, born = (rl[-1].split("|")[0], rl[-1].split("|")[1]) if rl and rl[-1] else (head, "?")
    if "{" in born: born = born[born.index("{") + 1:born.rindex("}")]
    commits = run(["git", "-C", path, "log", "--format=%h %cs %s", f"{born_sha}..{head}"]).split("\n")
    commits = [c for c in commits if c][:20]
    in_main = subprocess.run(["git", "-C", path, "merge-base", "--is-ancestor", head, main_sha],
                             capture_output=True).returncode == 0

    # successor: merged PR whose head is this HEAD
    pr = None
    try:
        for p in json.loads(run(["gh", "pr", "list", "--state", "merged", "--limit", "100", "--json",
                                 "number,headRefName,headRefOid,mergedAt,url,mergeCommit"], cwd=main_path)):
            if p["headRefName"] == branch and p["headRefOid"] == head: pr = p
    except Exception:
        pass

    dirty = [l for l in run(["git", "-C", path, "status", "--porcelain", "-uall"]).split("\n") if l]
    blockers = []
    if dirty: blockers.append(f"{len(dirty)} uncommitted/untracked file(s) would be LOST on removal")
    if not (pr or in_main): blockers.append("HEAD is not in main and no merged PR matches it: not merged")
    if me.get("locked"): blockers.append(f"worktree is LOCKED ({me['locked'] if me['locked'] is not True else 'no reason'})")

    fm = [
        "---", "kind: worktree-tombstone", f"repo: {repo}", f"worktree: {label}", f"branch: {branch}",
        f"head: {head}", f"born: {born}", f"ceased: {now.isoformat(timespec='seconds')}",
        f"reason: {reason or ('merged PR #%d' % pr['number'] if pr else 'commits are in main')}",
        f"successor: {pr['url'] if pr else 'main@' + main_sha[:7]}",
        f"removed_path: {path}", "---", ""]
    body = [f"# Tombstone: {label}", "",
            "A worktree ceased here. The function ended; this is the trace.", "",
            "## What it was", f"- repo `{repo}`, branch `{branch}`, born {born}",
            "- own commits:" + ("" if commits else " none recorded")]
    body += [f"  - `{c}`" for c in commits]
    body += ["", "## Why it ended",
             f"- {reason or ('PR #%d merged %s' % (pr['number'], pr['mergedAt'][:10]) if pr else 'all commits are in main (no PR)')}",
             f"- HEAD contained in main: {'yes' if in_main else 'no'}", "", "## Successor",
             f"- {pr['url'] if pr else 'main@' + main_sha[:7]}", "", "## Where the record lives",
             f"- branch `{branch}` is NOT deleted by this step",
             f"- commits reachable from `{head[:7]}`"]
    body += [f"- {a} session `{sid}`: `{tr}`" for a, sid, tr in sessions] or ["- no agent session found in herdr"]
    if dirty:
        body += ["", "## Not committed at the time (would be lost on removal)"] + [f"- `{l}`" for l in dirty[:40]]
    body += ["", "---", "AI-generated by herdr-oracle (Claude)."]
    text = "\n".join(fm + body) + "\n"

    vault = os.path.join(main_path, "ψ", "memory", "tombstones")
    dest_dir = vault if os.path.isdir(os.path.join(main_path, "ψ")) else os.path.expanduser(f"~/.herdr/tombstones/{repo}")
    dest = os.path.join(dest_dir, f"{now.strftime('%Y-%m-%d')}_{label}.md")
    n = 2
    while os.path.exists(dest):
        dest = os.path.join(dest_dir, f"{now.strftime('%Y-%m-%d')}_{label}-{n}.md"); n += 1

    print(text)
    print(f"destination: {dest}")
    for b in blockers: print(f"BLOCKER: {b}")
    if write:
        os.makedirs(dest_dir, exist_ok=True)
        open(dest, "x", encoding="utf-8").write(text)
        print("written." + ("  Blockers above still apply to removal." if blockers else ""))
    else:
        print("dry run - add --write to save it")

main()
