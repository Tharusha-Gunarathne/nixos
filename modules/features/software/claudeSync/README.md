# Claude Code shared setup (NixOS ⇄ Windows)

> Claude adapter guide. Maintained source: `agent-sync/claude/`. Export changes
> through `agent-sync/tools/sync_nixos.py` before rebuilding the NixOS module.
> See [the workspace guide](WORKSPACE-README.md) for the combined system and bootstrap.

One Claude Code ecosystem across a dual-boot machine:

| Where | Who | Claude home |
|---|---|---|
| NixOS | `linux-user` | `~/.claude` |
| Windows | `windows-user-a` | `C:\Users\windows-user-a\.claude` |
| Windows | `windows-user-b` (local admin) | `C:\Users\windows-user-b\.claude` |

The shared store is `E:\.claude-shared` (NixOS: `/mnt/E_Drive/.claude-shared`).
Two Claude accounts can be used; account (claude.ai) skills are copied into the
shared `skills/` so they survive switching accounts.

---

## What it does

- **Shared folders (junctions/symlinks):** `projects` (sessions — `/resume` shows
  both OSes), `skills`, `agents`, `commands`, `plans`, `file-history`, and
  `~/.claude-mem` (claude-mem memory database) all live on `E:`.
- **Install AND uninstall follow everywhere.** Every session start records what
  is installed here into `_sync/registry.jsonl` (append-only). Plugins,
  marketplaces, MCP servers and skills added on any OS/user get installed on the
  others; something removed since the last session gets removed everywhere.
  Latest event wins — reinstalling anywhere brings it back.
- **MCP servers per OS:** `_sync/shared.json → mcpServers` holds a `linux` and a
  `windows` launch command for each server.
- **Skill updates:** `skill-update.ts` refreshes shared skills from their GitHub
  upstreams (sources in `shared.json → skillSources`, plus anything installed
  with `npx skills`). Crash-safe swaps; last 3 old versions in `_sync/skill-history`.
- **OS context:** each session is told which OS it runs on, so Claude doesn't
  try Windows commands on NixOS or the reverse.
- **Sandbox:** a separate Claude config where nothing is shared or recorded.

### Files in `_sync/`

| File | Purpose |
|---|---|
| `bootstrap.ps1` | One-time Windows setup per user |
| `hook.ps1` | Windows SessionStart hook (sync on every session) |
| `shared.json` | Manifest: shared dirs, plugins, marketplaces, MCP servers, skill sources |
| `registry.jsonl` | Install/uninstall event log from every OS and user |
| `state/<os>-<user>.json` | Per-machine-user state (what was seen, held removals, failed installs) |
| `skill-update.ts`, `skill-sources.json` | Skill updater and its learned sources |
| `trash/` | Removed shared skills, kept 30 days |
| `skill-history/` | Previous skill versions |
| `claude-sandbox.ps1` | Windows sandbox launcher |
| `hook-windows.log`, `skill-update.log` | Logs |

NixOS side lives in the NixOS repo: `modules/features/software/claudeSync/`
(`default.nix`, `claude-shared.py`, the same `hook.ps1`/`bootstrap.ps1`/`shared.json`).
Files in `_sync/` are **overwritten on every rebuild** — change them in the repo.

---

## Setup

### NixOS

Already part of the system config. After changing anything in `claudeSync/`:

```bash
export NIXOS_LOCAL_CONFIG="$PWD/.env.local"
sudo --preserve-env=NIXOS_LOCAL_CONFIG nixos-rebuild switch --flake .#nixos --impure
```

### Windows — once per machine (as windows-user-b, admin)

Fast Startup must be **off**, or NixOS sees `E:` as dirty/read-only. Running
bootstrap from an **Administrator** PowerShell turns it off. Machine-wide, so
once is enough.

### Windows — once per user (windows-user-a, then windows-user-b), logged in as that user

1. Install on that user's PATH:
   - **Claude Code** (`claude`)
   - **Node.js** (`node`, `npx`) — context7, sequential-thinking, codegraph, playwright MCPs; fallback for skill updates
   - **uv** (`uv`, `uvx`) — serena, headroom MCPs
   - **git**
   - **bun** (optional, faster skill updates)
2. `claude` → `/login` with that user's account → exit.
3. Close **every** Claude window (bootstrap refuses to run otherwise).
4. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File E:\.claude-shared\_sync\bootstrap.ps1
   ```
5. Verify:
   - `E:\.claude-shared\_sync\state\windows-<user>.json` exists
   - `dir /AL %USERPROFILE%\.claude` lists junctions
   - `claude` → `/resume` shows NixOS sessions
   - `claude mcp list` shows the shared MCP servers
   - `E:\.claude-shared\_sync\hook-windows.log` has no new errors

Re-running bootstrap is safe at any time (e.g. after `shared.json` changes).

---

## Commands

### NixOS

| Command | What |
|---|---|
| `claude` | Wrapped Claude Code (runs the sync hook) |
| `claude-shared status` | Show sync state |
| `claude-shared sync` | Run a full sync now (also runs on rebuild) |
| `claude-shared removals --confirm` | Apply a held mass-removal |
| `claude-shared removals --restore` | Undo a held mass-removal (reinstall) |
| `skill-update --force` | Refresh shared skills from upstream now |
| `claude-sandbox [--reset] [args]` | Isolated Claude (`~/.claude-sandbox`) |
| `nix shell nixpkgs#powershell -c python3 tests/sync_test.py` | E2E test (run inside `claudeSync/`) |

### Windows (PowerShell)

| Command | What |
|---|---|
| `powershell -ExecutionPolicy Bypass -File E:\.claude-shared\_sync\bootstrap.ps1` | Set up / repair this user |
| `... bootstrap.ps1 -Uninstall` | Remove junctions, copy data back locally (shared store untouched) |
| `& E:\.claude-shared\_sync\hook.ps1` | Run the sync manually |
| `& E:\.claude-shared\_sync\hook.ps1 -ConfirmRemovals` | Apply a held mass-removal |
| `& E:\.claude-shared\_sync\hook.ps1 -RestoreRemovals` | Undo a held mass-removal |
| `& E:\.claude-shared\_sync\claude-sandbox.ps1 [-Reset] [args]` | Isolated Claude (`~\.claude-sandbox`) |

### Turning sharing off for one session

Set `CLAUDE_SHARED_OFF=1` (or use a different `CLAUDE_CONFIG_DIR`): the hook
then records and changes nothing.

---

## MCP servers

| Server | NixOS | Windows | Needs on Windows |
|---|---|---|---|
| serena | `uvx serena-agent` | same | uv |
| sequential-thinking | `npx` | `cmd /c npx` | Node |
| context7 | `npx` | `cmd /c npx` | Node |
| headroom | `headroom` (uvx-pinned 0.39.1) | `uvx --from headroom-ai[all]==0.39.1` | uv (Python 3.13 fetched by uv) |
| codegraph | `codegraph` (~/.codegraph install) | `cmd /c npx @colbymchenry/codegraph@1.1.6` | Node 20–24 |
| playwright | `npx @playwright/mcp` + Edge | `cmd /c npx @playwright/mcp --browser msedge` | Node, Edge (built in) |
| thunder-compute, higgsfield | HTTP | HTTP (copied as-is) | — |

Adding a new MCP server for both OSes: add it to `shared.json → mcpServers`
with `linux` and `windows` entries, rebuild NixOS, re-run bootstrap on each
Windows user. A server without a `windows` entry is copied only if it can run
there unchanged; otherwise `hook-windows.log` says
`MCP server X can't run here; add a 'windows' entry for it in shared.json`.

Windows rule: `npx`, `bunx`, `npm`, `pnpm`, `yarn` are `.cmd` shims, so they
must be launched as `cmd /c npx ...`.

---

## ⚠ Warnings

- **Never delete the junctions with `Remove-Item -Recurse`, a cleanup tool, or
  Explorer "delete folder" inside `%USERPROFILE%\.claude`.** PowerShell 5.1
  follows junctions and deletes the shared data for every OS and user. Use
  `bootstrap.ps1 -Uninstall`, or `cmd /c rmdir <junction>` (removes only the link).
- **Uninstalls spread everywhere.** Removing a plugin/skill/MCP on one OS or
  user removes it on all. Test experiments in the sandbox instead.
- **Mass-removal guard:** if more than 10 items (or everything) vanish at once,
  nothing is removed — it's held until you `--confirm` / `-ConfirmRemovals` or
  `--restore` / `-RestoreRemovals`. An unreadable/corrupt config is treated as
  "no change", never as "uninstalled".
- **Don't run Claude in both Windows users at once** (fast user switching).
  They share one claude-mem SQLite database on `E:`; two workers writing can
  corrupt it. Sign the other user out first.
- **Shut down fully before switching OS.** No hibernate, and Fast Startup off,
  or NTFS stays dirty and NixOS mounts `E:` read-only.
- **Don't edit `_sync/*` on the drive** — the next `nixos-rebuild` overwrites
  it. Edit the NixOS repo.
- **Running bootstrap "as administrator" with another account's credentials**
  sets up *that* account's profile, not yours. Run per-user bootstrap in a
  normal shell of the user it is for.
- **Linux-only paths** (`/mnt`, `/home`, `/nix`, `/etc`...) in an MCP spec make
  it Linux-only; Windows paths in `windowsSettings` are Windows-only.
- **codegraph versions:** Windows is pinned to 1.1.6 to match the NixOS
  install, since both read the same `.codegraph/` index in projects on `E:`.
  If NixOS codegraph updates, bump the version in `shared.json` too.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `/resume` doesn't show other OS's sessions | Re-run bootstrap; check `dir /AL %USERPROFILE%\.claude` |
| MCP missing on Windows | Check `hook-windows.log`; install uv/Node; re-run bootstrap |
| `E:` read-only on NixOS | Boot Windows, shut down fully (not restart-to-Linux from hibernate); check Fast Startup is off |
| Something vanished everywhere | `_sync/trash/` (skills, 30 days); `registry.jsonl` shows who removed it; reinstall anywhere to bring it back |
| Bootstrap: "Close every Claude Code window first" | Close Claude, check Task Manager for `claude.exe` |
| Plugins not installed on Windows | `claude` must be on PATH; re-run bootstrap |
