# Codebase intake

Run this **once**, by the lead agent, right after installing the team
(`install.sh`). Goal: fill the `## Project brief` section of the installed team
manual (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md`, depending on the harness) so the
whole team is grounded in *this* project.

**Why it matters:** specialists do not read the whole repo or inherit the manual
automatically — the lead injects the brief into every delegation. An empty brief
means the team is flying blind. Honor team principles 2 and 3 (don't reinvent;
explore the framework first) — learn what's already here before building.

## 1. Gather
Read the repo. For a non-trivial codebase, delegate the scan to a read-only
explorer/architect. Collect:

- [ ] **Stack** — languages, runtime, package manager (read manifests/lockfiles:
      `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, …)
- [ ] **Frameworks / libraries** — the major ones + versions, and for each: the
      real capabilities, limits, and idioms the team must use rather than reinvent
      or fight. Prefer the library's own docs/source over guessing.
- [ ] **Structure** — where code lives, entry points, module layout
- [ ] **Run / build / test** — the exact commands (from scripts, Makefile, CI config)
- [ ] **Conventions** — lint/format config, naming, established patterns
- [ ] **Reuse first** — existing utils, components, design system to use instead of
      writing new
- [ ] **Constraints / gotchas** — anything that bites

For an empty/greenfield project, capture the *intended* stack and conventions instead.

## 2. Write
Fill the `## Project brief` section of the installed manual with the findings.
Replace every `<placeholder>`. Keep it concise — it is injected on every handoff.

## 3. Confirm
Report the brief back to the human and confirm the team is ready. The usual first
step is `pm` → spec.
