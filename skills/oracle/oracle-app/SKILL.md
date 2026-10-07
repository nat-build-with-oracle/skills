---
name: oracle-app
description: "Build an oracle's own Mac app (agent app like Neo/Pulse/Nexus: Work, Inbox, PRs, Issues, Memory, Map, Trace, widget, Share, MCP memory server) from oracle-app-kit, and keep the portal (ARRA Oracles) building. Use when an oracle says 'build my app', 'oracle-app new', 'make an app for <oracle>', 'rebuild the apps', 'check my app'. Do NOT use for App Store/TestFlight shipping or the Chrome extension."
---

# /oracle-app — thin pointer

The skill lives **in the kit**, versioned with the generator and scripts it drives. This file only finds it.

```bash
KIT=$(ghq list -p --exact Soul-Brews-Studio/oracle-app-kit) || { ghq get -p Soul-Brews-Studio/oracle-app-kit; KIT=$(ghq list -p --exact Soul-Brews-Studio/oracle-app-kit); }
git -C "$KIT" fetch -q origin
```

1. Read `$KIT/skills/oracle-app/SKILL.md` and follow it exactly — preflight, `new`, `build`, `check`, `portal`.
   If the main checkout does not have it yet, read it from the open PR branch:
   `git -C "$KIT" show origin/feat/oracle-app-skill:skills/oracle-app/SKILL.md`.
2. Never work in `$KIT`'s main checkout: cut a worktree first (the kit's SKILL.md §0 says how).
3. Arguments given to `/oracle-app` (`new <Name> …`, `build`, `check <Name>`, …) map 1:1 to the kit's sections.
