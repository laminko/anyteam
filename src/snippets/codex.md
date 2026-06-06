## Delegating & fan-out

Delegate by spawning subagents explicitly: the lead receives a task, then spawns each specialist as a subagent. Codex's default `max_depth` is 1, which means a flat hub-and-spoke topology — the lead spawns workers; workers do not re-spawn. This matches the team model exactly.

**Roster is user-global.** The specialists are installed under `~/.codex/agents/` (not inside the project). This is intentional: it avoids the project-scope spawn bug (Codex issue #14579) and means the same team is available across all your projects without per-project setup.

**Concurrency rule — parallel reads, sequential writes.** Read-only work (research, browsing, exploration, audits, search) MAY fan out in parallel — spawn multiple specialists in one turn. Any work that **writes or updates** files (implementation, refactor, migration, doc edits) runs **one agent at a time, sequentially** — never two writers in flight at once, even on disjoint files. Run dependent work as a pipeline (one specialist's output feeds the next).

## Scaling specialists (fan-out)
`be` and `fe` are ROLES, not single agents — shard work into vertical slices / resources
(`/api/v1/brand` → `be-brand`, each FE area → `fe-<area>`). Fan-out obeys the **concurrency
rule above**: reads parallel, writes sequential.

- **Read / research / audit fan-out is parallel.** `uiux-research`, `uiux-audit`, and architect exploration may be spawned concurrently (cap at ~3–5 so results stay synthesizable).
- **Write / implementation fan-out is sequential.** Spawn implementation specialists **one at a time** even when slices are disjoint: finish `be-brand`, integrate, then spawn `be-category`.

Rules that keep sequential writes clean:
1. **One writer in flight.** Never have two write/update agents running at once. Pipeline them.
2. **Disjoint files per slice.** Give each instance a non-overlapping set of files/modules. The Architect's component boundaries define these seams — shard along them.
3. **Cross-cutting files** (route registration, DI container, shared base schema, a single migration) are wired up by the lead after slice instances finish, or assigned to one dedicated instance.
4. **Granularity**: per-resource is the sweet spot. Per-endpoint inside one resource usually backfires (shared model/router → file conflicts).
5. Label instances by slice (`be-brand`, `fe-settings`) for traceability.
