# NixOS Flake Configuration

A modular NixOS + Home Manager configuration managed with flakes and structured
using flake-parts and import-tree.

## Repository Layout

```
.
├── flake.nix
├── flake.lock
├── plugins/
│   ├── sources/
│   └── noctalia/
└── modules/
    ├── systems.nix
    ├── features/
    │   ├── core/
    │   ├── hardware/
    │   ├── software/
    │   │   └── noctalia/
    │   │       └── integrations/
    │   └── user/
    └── hosts/
        └── nixos/
```

## Structure

### `modules/`

All NixOS and Home Manager modules live here. Every `.nix` file is automatically
imported by `import-tree`. Each file exposes a `flake.nixosModules.<name>` attribute
and is explicitly imported in `modules/hosts/nixos/configuration.nix`.

### `modules/features/core/`

System-wide foundational options and settings.

### `modules/features/hardware/`

Hardware-specific configuration including GPU, audio, networking, boot, display,
and hardware-level system services (power management, thermal control, undervolting).

### `modules/features/software/`

Per-application configuration modules. Each module covers only the concerns of
that application — no shell-specific logic belongs here.

### `modules/features/software/noctalia/`

The Noctalia desktop shell module. Handles shell installation, config seeding,
bidirectional sync, git auto-commit, and plugin installation via
`plugin-settings.nix` (which symlinks all plugins into `xdg.configFile` and
applies any necessary source patches).

### `modules/features/software/noctalia/integrations/`

Shell-specific hooks for individual applications. Each file here contains only
what Noctalia needs from or injects into a given app. All integration modules are
guarded by `lib.mkIf config.myConfig.shell.noctalia`.

### `modules/features/user/`

User-level environment configuration that is not application-specific. Covers
GTK theming and cursor (`gtk.nix`), XDG session variables and user directories
(`variables.nix`), and custom desktop entries (`desktop-entries.nix`).

### `modules/hosts/nixos/`

Host-specific wiring. Imports all feature modules and sets machine-level options.

### `plugins/noctalia/`

A local flake that pins the Noctalia shell and its plugins as independent inputs,
allowing them to be updated separately from the main flake.

### `plugins/sources/`

A local flake that centralizes pinned non-flake source trees consumed by modules
(for example GitHub sources previously fetched via `fetchFromGitHub`).
It also centralizes pinned binary release metadata (such as Lotion and XDM
`.deb` URLs and hashes) under `releaseAssets`.

## Shell Toggle

The active desktop shell is controlled by a single boolean option:

```nix
myConfig.shell.noctalia = true; # or false
```

Setting this to `false` disables Noctalia and all its application integrations
atomically without modifying any application module.

## Key Options

| Option                        | Type    | Default                          | Description                          |
| ----------------------------- | ------- | -------------------------------- | ------------------------------------ |
| `myConfig.primaryUser`        | string  | `"tharusha-gunarathne"`          | Primary user account                 |
| `myConfig.primaryUid`         | int     | `1000`                           | Primary user UID                     |
| `myConfig.repoRoot`           | string  | `/home/<username>/nixos-configs` | Absolute path to this repo           |
| `myConfig.isUnderVoltEnabled` | bool    | `true`                           | Enable CPU undervolting              |
| `myConfig.storage.rootUuid`   | string  | host-specific UUID               | Root filesystem UUID                 |
| `myConfig.storage.bootUuid`   | string  | host-specific UUID               | Boot filesystem UUID                 |
| `myConfig.storage.dataDrives` | list    | host-specific UUID list          | Additional mounted drives            |
| `myConfig.shell.noctalia`     | bool    | `true`                           | Enable Noctalia shell integrations   |

## Build and Apply

```bash
# Validate before applying
nix build .#nixosConfigurations.nixos.config.system.build.toplevel --dry-run

# Apply
sudo nixos-rebuild switch --flake .#nixos
```

## Maintenance

```bash
# Update all inputs
nix flake update

# Update only Noctalia and its plugins
nix flake update noctalia

# Update only centralized source registry inputs
nix flake update sources

# Format all Nix files
nix fmt

# Show all flake outputs
nix flake show
```

## Updating `fetchFromGitHub` Hashes

When a pinned GitHub source gets a new release/tag, update both `rev` and `hash`.
This applies to any entry in `plugins/sources/flake.nix` under `sourcePins`.

### Method 1: Prefetch (quick)

1. Build the archive URL for the tag/commit you want:

```bash
nix-prefetch-url --unpack https://github.com/<owner>/<repo>/archive/refs/tags/<tag>.tar.gz
```

2. Copy the last printed line (the hash) into `hash`.
3. Update `rev` to the same tag/commit.

Example:

```bash
nix-prefetch-url --unpack https://github.com/Samillion/ModernZ/archive/refs/tags/v1.0.tar.gz
```

### Method 2: Let Nix tell you the hash (most reliable)

1. Set a temporary fake hash:

```nix
hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
```

2. Evaluate:

```bash
nix flake check --no-build
```

3. Copy the `got:` hash from the error output into `hash`.
4. Re-run `nix flake check --no-build` to confirm.

### Rules of thumb

1. Hash must match the exact source for the exact `rev`.
2. Every `rev` change requires a new hash.
3. Prefer tags over moving branches (`main`) for reproducible builds.

## Troubleshooting

1. Run with `--show-trace` to get the full error location.
2. If a HM option is missing, check for `config` shadowing — capture NixOS-scope
   values in outer `let` bindings before entering `home-manager.users` blocks.
3. If the same file is managed by two modules, one will fail at activation.
4. If evaluation passes but activation fails, check `journalctl --user -xe`.
```.