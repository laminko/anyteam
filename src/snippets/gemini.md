## Delegating & fan-out

Delegate by auto-routing on `description` (Gemini CLI dispatches based on matching the task to each agent's description) or by prefixing a prompt with `@agent-name` (e.g. `@architect`). Give each specialist the context it needs — agents start with a clean context and only know what you tell them.

**Gemini-specific notes:**
- **Flat subagents**: Gemini subagents cannot sub-delegate — they are leaf nodes. This fits hub-and-spoke naturally: only the lead (your main session) delegates; specialists report back to you.
- **Tool restrictions**: `full`-policy roles inherit all tools. `read-only` roles (uiux-audit) and `research` roles (uiux-research) receive an explicit tool allowlist. **ASSUMPTION**: the tool names in the agent files (`read_file`, `read_many_files`, `search_file_content`, `glob`, `run_shell_command`, `web_fetch`, `google_web_search`) are best-guess names based on common Gemini CLI conventions — they are **unverified** against the live tool registry. Correct them with a one-line edit to `src/harnesses.json` after a smoke test confirms the actual names.

**Concurrency rule — parallel reads, sequential writes.** Read-only work (research, browsing, exploration, audits, search) MAY fan out in parallel — multiple delegations in one message. Any work that **writes or updates** files (implementation, refactor, migration, doc edits) runs **one agent at a time, sequentially** — never two writers in flight at once, even on disjoint files. Run dependent work as a pipeline (one specialist's output feeds the next).

## Scaling specialists (fan-out)
`be` and `fe` are ROLES, not single agents — shard work into vertical slices / resources
(`/api/v1/brand` → `be-brand`, each FE area → `fe-<area>`). Fan-out obeys the **concurrency
rule above**: reads parallel, writes sequential.

- **Read / research / audit fan-out is parallel.** `uiux-research`, `uiux-audit`,
  and architect exploration reads may run as many concurrently as useful (cap at ~3–5
  so results stay synthesizable).
- **Write / implementation fan-out is sequential.** Run implementation instances **one at a
  time** even when slices are disjoint: dispatch `be-brand`, let it finish and integrate,
  then dispatch `be-category`. Sharding still matters — it's how you plan the sequence and
  keep each step small — it just doesn't authorize concurrent writers.

Rules that keep sequential writes clean:
1. **One writer in flight.** Never have two write/update agents running at once. Pipeline them.
2. **Disjoint files per slice.** Even sequentially, give each instance a non-overlapping set of files/modules. The Architect's component boundaries define these seams — shard along them.
3. **Cross-cutting files** (route registration, DI container, shared base schema, a single migration) are wired up by the lead after the slice instances finish, or assigned to one dedicated instance.
4. **Granularity**: per-resource is the sweet spot. Per-endpoint inside one resource usually backfires (shared model/router → file conflicts).
5. Label instances by slice (`be-brand`, `fe-settings`) for traceability.
