# AgentSync private shared store

This directory holds the shared runtime data for **Claude and Codex**.
Its historical `.claude-shared` name is retained so existing Linux links,
Windows junctions and installed hooks continue working.

**Source, setup instructions and maintenance:** [agent-sync/README.md](agent-sync/README.md).

After a source-layout update, close both agents and apply the new bootstrap
described in that guide. Compatibility deployment refuses active reservations;
leave them intact and let the owning session finish.

| Location | Purpose | Put in Git? |
|---|---|---|
| `agent-sync/` | Maintained source, tests and documentation | Yes, after source checks |
| `_sync/` | Compatibility launchers, registry, archives and generated state | No |
| `projects/`, `file-history/` | Private native conversations and history | No |
| `claude-mem/` | Memory database, logs and worker state | No |
| `skills/`, `agents/`, `commands/`, `plans/` | Existing installed capabilities and runtime content | No |
| `_sync/backups/`, old memory snapshots | Private recovery data | No |

Use `claude`, `codex` or `codex resume` in a project after bootstrap and a fresh
terminal. Claude and one Codex session may run in different projects. Exit the
current agent before switching within the same project.

Headroom uses the coordinated `hcodex` shortcut, not plain `headroom wrap codex`.
The same claude-mem storage is configured for both agents; actual Codex capture
and cross-agent recall still require verification.

Do not delete junctions recursively, rename this store, restore databases over
running applications or upload its contents. Only `agent-sync/` is the GitHub
source project. The root `.gitignore` excludes runtime data as a second guard.

This overview is maintained at `agent-sync/docs/workspace.md` and deployed by
the compatibility installer. The exported Nix module also ships a copy on rebuild.
