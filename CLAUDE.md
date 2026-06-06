# Contributing to this repo

This repo is the **source + build system** for a portable, installable hub-and-spoke specialist team distributed across multiple AI coding harnesses. Read this file before making any changes.

## What lives where

| Path | Purpose |
|------|---------|
| `src/roles/*.md` | Canonical role definitions (neutral frontmatter). Edit roles here. |
| `src/manual.md` | The shippable team manual (harness-neutral). Edit the manual here. |
| `src/snippets/` | Per-harness splice content (e.g. `claude-code.md` for delegation/fan-out). |
| `src/harnesses.json` | Per-harness mapping config. |
| `dist/` | **GENERATED — never hand-edit.** Rebuilt by `generate.py`. |
| `generate.py` | stdlib-only Python3 generator. Renders `src/` → `dist/<harness>/`. |
| `install.sh` | Pure-bash installer. Copies `dist/<harness>/` into a user's project. Must stay bash-3.2-clean. |
| `.claude/agents/` | Claude Code agent roster — dogfooded from `dist/claude-code/.claude/agents/`. |

**The golden rule:** `dist/` is generated output. If you need to change a role or the manual, edit `src/` and re-run `generate.py` — never edit `dist/` directly.

## Team principles (apply to every agent, every task)
1. **KISS** — the simplest thing that works. Smallest change that solves the problem; no gold-plating, no speculative abstraction.
2. **Don't reinvent the wheel** — reuse existing code, libraries, and framework features before writing anything custom. Custom code is the last resort, and must be justified.
3. **Explore the framework/library first** — before designing or building on a tool, learn its real capabilities and limitations (read its source/docs, not guesses) so we use it idiomatically and don't fight it.
4. **Clean, professional UI/UX** — production-grade, accessible, visually consistent. Avoid generic AI aesthetics.

_(More principles will be added over time — treat this list as living.)_

## Hub-and-spoke team (this repo dogfoods it)

This repo is built using the same hub-and-spoke specialist team it ships. The orchestrator (main Claude thread) delegates to specialist subagents; specialists do not talk to each other.

**Roster** (defined in `.claude/agents/`, sourced from `src/roles/`):

| Agent | Role | Owns |
|-------|------|------|
| `pm` | Product Manager | Spec, scope, acceptance criteria, task breakdown |
| `architect` | Architect | Data model, API contract, component boundaries |
| `be` | Backend Engineer | Server-side implementation |
| `fe` | Frontend Engineer | Client / UI implementation |
| `uiux-audit` | UI/UX Auditor | Read-only usability/accessibility review |
| `uiux-research` | UI/UX Researcher | Design patterns and evidence before building |

The full orchestrator operating manual — including model policy, default feature flow, concurrency rules, and conventions — is in `src/manual.md`.

## Refreshing the dogfood roster

The repo's `.claude/agents/` files are generated output. After editing `src/roles/*.md`, rebuild and refresh **only the roster** (not the manual) with:

```bash
python3 generate.py && cp -f dist/claude-code/.claude/agents/*.md .claude/agents/
```

This regenerates `dist/claude-code/` and overwrites `.claude/agents/` with the fresh output. Commit `dist/` and `.claude/agents/` together so they stay in sync.

> Do **not** use `install.sh --dir . --force` here: it would also copy the shippable
> `dist/claude-code/CLAUDE.md` over this contributor `CLAUDE.md` (same filename, different
> file). The `cp` above refreshes only the agent roster and leaves this doc untouched.

## Constraints
- `generate.py` must be Python3 stdlib-only (no third-party dependencies).
- `install.sh` must be compatible with bash 3.2 (macOS system bash).
