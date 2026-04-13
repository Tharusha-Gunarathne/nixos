# NixOS Flake Configuration

A modular NixOS + Home Manager configuration managed with flakes and structured
using flake-parts and import-tree.

## Repository Layout

```
.
├── flake.nix
├── flake.lock
├── plugins/
│   └── noctalia/
└── modules/
    ├── systems.nix
    ├── features/
    │   ├── core/
    │   ├── hardware/
    │   └── software/
    │       └── noctalia/
    │           └── integrations/
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

Hardware-specific configuration including GPU, audio, networking, boot, and display.

### `modules/features/software/`

Per-application configuration modules. Each module covers only the concerns of
that application — no shell-specific logic belongs here.

### `modules/features/software/noctalia/`

The Noctalia desktop shell module. Handles shell installation, config seeding,
bidirectional sync, and git auto-commit.

### `modules/features/software/noctalia/integrations/`

Shell-specific hooks for individual applications. Each file here contains only
what Noctalia needs from or injects into a given app. All integration modules are
guarded by `lib.mkIf (config.myConfig.shell == "noctalia")`.

### `modules/hosts/nixos/`

Host-specific wiring. Imports all feature modules and sets machine-level options.

### `plugins/noctalia/`

A local flake that pins the Noctalia shell and its plugins as independent inputs,
allowing them to be updated separately from the main flake.

## Shell Toggle

The active desktop shell is controlled by a single option:

```nix
myConfig.shell = "noctalia"; # or "none"
```

Setting this to `"none"` disables Noctalia and all its application integrations
atomically without modifying any application module.

## Key Options

| Option | Type | Default | Description |
|---|---|---|---|
| `myConfig.username` | string | `"tharusha-gunarathne"` | Primary user account |
| `myConfig.repoRoot` | string | `/home/<username>/nixos-configs` | Absolute path to this repo |
| `myConfig.shell` | enum | `"noctalia"` | Active desktop shell |

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

# Format all Nix files
nix fmt

# Show all flake outputs
nix flake show
```

## Troubleshooting

1. Run with `--show-trace` to get the full error location.
2. If a HM option is missing, check for `config` shadowing — capture NixOS-scope
   values in outer `let` bindings before entering `home-manager.users` blocks.
3. If the same file is managed by two modules, one will fail at activation.
4. If evaluation passes but activation fails, check `journalctl --user -xe`.
```