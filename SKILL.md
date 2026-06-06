---
name: bootstrap-team
description: Bootstrap the portable hub-and-spoke specialist team (pm, architect, be, fe, uiux-audit, uiux-research) into a project — installs the agent roster + operating manual into the current AI coding harness, then runs a codebase intake so the team follows the project's stack, frameworks, and conventions. Use when starting the team on a new or existing project, onboarding the team, or when the user says "bootstrap team", "onboard the team", or "set up the team here".
---

# Bootstrap Team

Installs a hub-and-spoke specialist team into the current project and grounds it in
the codebase. Two halves: a deterministic **install** (files) and a model-driven
**intake** (understanding). Do both — install alone leaves the team flying blind.

## 1. Install (deterministic)
Run the bundled installer against the target project. `<SKILL_DIR>` is this skill's
base directory (provided when the skill loads — it is the repo root):

```bash
bash <SKILL_DIR>/install.sh [--harness <id>] [--dir <project>]
```

With no `--harness` it auto-detects from the project; inside Claude Code that resolves
to `claude-code`. Supported harnesses: **claude-code, opencode, gemini, codex, pi**.
It copies the 6 agents into the harness's roster directory (no-clobber) and writes the
team manual as the harness's instruction file. Report what was added/skipped and any
per-harness note the installer prints (Codex installs the roster user-level; Pi needs
the `@tintinweb/pi-subagents` extension).

## 2. Intake (you, the lead)
Follow `<SKILL_DIR>/INTAKE.md`: scan the codebase and fill the `## Project brief`
section of the installed manual so every specialist is grounded. They do NOT inherit
the manual — the lead injects this brief into each delegation.

## 3. Confirm
Report the brief back to the human and confirm the team is ready. The first step is
usually `pm` → spec.

## Notes
- **Hub-and-spoke:** the human talks to the lead (main thread); the lead delegates to
  specialists and synthesizes. Specialists don't talk to each other.
- The roster + manual are **generated** from `src/` — to evolve the team, edit `src/`
  and run `python3 generate.py` (see `CLAUDE.md`). Never edit `dist/` by hand.
