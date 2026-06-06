## Delegating & fan-out

Delegate via the **Task tool** (OpenCode routes automatically based on each subagent's `description`) or by `@mention` (e.g. `@architect`). All eight specialists are `mode: subagent` — your main session is the primary orchestrator; specialists do not sub-delegate.

Per-agent tool restrictions are enforced via the `tools` and `permission` keys in each agent file: read-only roles cannot write or edit files; research roles cannot edit; the `audit` role (`security-audit`) can run shell scanners but is held read-only via `permission.edit: deny`. Full-policy roles inherit all available tools.

**Concurrency rule — parallel reads, sequential writes.** Read-only work (research, browsing, exploration, audits, search) MAY fan out in parallel — multiple Task calls in one message. Any work that **writes or updates** files (implementation, refactor, migration, doc edits) runs **one agent at a time, sequentially** — never two writers in flight at once, even on disjoint files. Run dependent work as a pipeline (one specialist's output feeds the next).

## Scaling specialists (fan-out)
`be` and `fe` are ROLES, not single agents — shard work into vertical slices / resources
(`/api/v1/brand` → `be-brand`, each FE area → `fe-<area>`). Fan-out obeys the **concurrency
rule above**: reads parallel, writes sequential.

- **Read / research / audit fan-out is parallel.** `uiux-research`, `uiux-audit`,
  `security-research`, `security-audit`, and architect exploration reads may run as many
  concurrently as useful (cap at ~3–5 so results stay synthesizable). `security-audit`
  runs read-only scanners only — never state-changing commands.
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
