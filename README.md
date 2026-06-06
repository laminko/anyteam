# anyteam

**One AI dev team, any agent harness.** A portable **hub-and-spoke specialist team**
you can install into any of several AI coding harnesses with one command. The team is a small roster of role-specialised
subagents — Product Manager, Architect, Backend, Frontend, and two UI/UX roles — plus
an operating manual that tells the lead agent how to delegate to them and synthesise
their work.

One canonical source, rendered into each harness's native subagent format. Define the
team once; install it everywhere.

## Supported harnesses

Only harnesses with a **file-definable subagent roster** (where a lead can delegate to
predefined named specialists) are supported.

| Harness | Roster location | Manual file | Model tiering |
|---|---|---|---|
| **Claude Code** | `.claude/agents/*.md` | `CLAUDE.md` | `opus` / `sonnet` |
| **OpenCode** | `.opencode/agents/*.md` | `AGENTS.md` | `anthropic/claude-*` |
| **Gemini CLI** | `.gemini/agents/*.md` | `GEMINI.md` | `gemini-2.5-pro` / `flash` |
| **Codex CLI** | `~/.codex/agents/*.toml` (user-level) | `AGENTS.md` | `gpt-5-codex` + reasoning effort |
| **Pi** | `.pi/agents/*.md` | `AGENTS.md` | `anthropic/claude-*` |

The lead role runs on the heavy tier; `pm` and `architect` are heavy, the rest are light.
Model ids are sensible defaults — tune them in [`src/harnesses.json`](src/harnesses.json)
and re-run the generator (see [Contributing](#contributing)).

## Install

```bash
git clone https://github.com/laminko/anyteam.git
cd anyteam
bash install.sh                  # auto-detect the harness from the target project
```

Or be explicit:

```bash
bash install.sh --harness claude-code       # one harness
bash install.sh --harness opencode,pi       # several
bash install.sh --all                        # every supported harness
bash install.sh --dir /path/to/project       # target a different project
bash install.sh --dry-run                    # show what would happen, copy nothing
```

The installer is **no-clobber by default** (it skips files that already exist; pass
`--force` to overwrite) and is plain `bash` (3.2-compatible — works with macOS system bash).

### Per-harness notes
- **Codex** installs the roster **user-level** at `~/.codex/agents/` (honors `$CODEX_HOME`)
  to avoid a project-scope spawn bug; the manual still lands in the project as `AGENTS.md`.
- **Pi** needs the subagents extension — after install, run
  `pi install npm:@tintinweb/pi-subagents`. The installer reminds you.

## After install: ground the team

Installing copies files; it does not teach the team your codebase. Run the one-time
**intake** ([`INTAKE.md`](INTAKE.md)): the lead scans the repo and fills the
`## Project brief` section of the installed manual (stack, frameworks, run/build/test,
conventions, …) so every specialist inherits the project's real context. In Claude Code,
the bundled [`SKILL.md`](SKILL.md) wraps install + intake as a `/bootstrap-team` skill.

## The team

| Agent | Role | Owns |
|---|---|---|
| `pm` | Product Manager | Spec, scope, acceptance criteria (WHAT / WHY) |
| `architect` | Architect | Data model, API contract, component boundaries (HOW) |
| `be` | Backend Engineer | Server-side implementation against the contract |
| `fe` | Frontend Engineer | Client / UI against the contract |
| `uiux-audit` | UI/UX Auditor | Read-only usability / accessibility review |
| `uiux-research` | UI/UX Researcher | Patterns / evidence before building |

The human talks to the **lead** (the main agent thread); the lead delegates to specialists
and synthesises their results. Specialists do not talk to each other.

## Contributing

The repo is the **source + build system**, not a pile of hand-written configs:

- Edit roles in [`src/roles/*.md`](src/roles) and the shippable manual in
  [`src/manual.md`](src/manual.md).
- Per-harness mapping lives in [`src/harnesses.json`](src/harnesses.json).
- [`generate.py`](generate.py) (Python 3, standard library only) renders `src/` →
  `dist/<harness>/`. The committed `dist/` is what `install.sh` copies.
- **Never hand-edit `dist/`.** Run `python3 generate.py`; CI fails on drift
  (`python3 generate.py --check`).

See [`CLAUDE.md`](CLAUDE.md) for the full contributor guide.

## License

[MIT](LICENSE)
