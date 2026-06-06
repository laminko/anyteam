# Codebase intake

Run this **once**, by the lead agent, right after installing the team
(`install.sh`). Goal: fill the `## Project brief` section of the installed team
manual (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md`, depending on the harness) so the
whole team is grounded in *this* project.

**Why it matters:** specialists do not read the whole repo or inherit the manual
automatically — the lead injects the brief into every delegation. An empty brief
means the team is flying blind. Honor team principles 2 and 3 (don't reinvent;
explore the framework first) — learn what's already here before building.

**The rule for this intake: scan first, then ask. Never assume.** Gather everything
the repo actually states, then ask the human — explicitly — for anything the scan
could not determine or left ambiguous. Do not write a value you had to guess: an
unanswered field is a question for the human, not a blank to fill in.

## 1. Scan (gather what the repo states)
Read the repo. For a non-trivial codebase, delegate the scan to a read-only
explorer/architect. For each item below, record what you found **with evidence** (the
file it came from) **or** mark it **unknown / ambiguous** to carry into step 2:

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
- [ ] **Constraints / gotchas** — anything in the code that bites

## 2. Ask (fill the gaps explicitly — do not assume)
Show the human what the scan found, then ask — explicitly, one clear question per gap
— for everything the repo could not tell you. **Always ask** for these; they are never
fully in the code:

- **Product goal / intent** — what this is and who it's for
- **Deploy / runtime target** — where it runs, which environments
- **Priorities & non-goals** — what matters now, what's out of scope
- **Gotchas the code doesn't show** — anything that bites that a scan won't reveal

Also **confirm, never assume,** anything the scan found only ambiguously — e.g. which
of several test commands is canonical, or which of two competing patterns to follow.
For a greenfield/empty repo the scan finds little, so most fields come from the human:
ask for the *intended* stack, structure, and conventions.

## 3. Write
Fill the `## Project brief` section of the installed manual from the scan **plus** the
human's answers. Replace every `<placeholder>`. For any field the human explicitly
left open, write `TBD` — never a guess. Keep it concise: it is injected on every
handoff.

## 4. Confirm
Report the brief back to the human and confirm the team is ready. The usual first
step is `pm` → spec.
