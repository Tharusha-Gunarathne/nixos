# NixOS Flake Configuration

This repository contains a modular NixOS + Home Manager configuration managed with flakes.

## Goals

- Keep system and user settings separated.
- Organize features into small reusable modules.
- Make configuration easy to read, extend, and version-control.

## Repository Layout

- flake.nix: Flake entrypoint and input wiring.
- flake.lock: Locked input versions for reproducible builds.
- system/: NixOS system-level modules.
- home/: Home Manager user-level modules.
- pkgs/: Feature modules grouped by component (GTK, Niri, Nautilus, Noctalia, Kitty).
- hardware/: Machine-generated hardware configuration (intentionally ignored in git).

## Module Responsibilities

### system/

System-wide concerns only, such as:

- Boot and EFI settings.
- Networking.
- Locale and timezone.
- Drivers (including GPU setup).
- Core services and system packages.
- User account and groups.
- Importing system-side feature modules from pkgs/.

### home/

User-session concerns only, such as:

- User packages and shell/app preferences.
- Environment variables.
- Git settings.
- Importing Home Manager feature modules from pkgs/.

### pkgs/

Feature-oriented module grouping:

- gtk/
  - gtk-system.nix: system GTK packages.
  - gtk-home.nix: user GTK and dconf settings.
- niri/
  - niri-system.nix: compositor enablement.
  - niri-home.nix: user config file deployment.
  - config.kdl: compositor configuration source.
- nautilus/
  - nautilus-system.nix: Nautilus services and session wiring.
  - nautilus-home.nix: Home Manager deployment of user extension scripts.
  - nautilus-extensions/: place custom Nautilus Python extensions here.
- noctalia/
  - noctalia.nix: shell module and JSON config wiring.
  - noctalia-plugins.nix: plugin source mapping.
  - settings.json and plugins.json: shell/plugin settings.
- kitty/
  - kitty.nix: terminal configuration.

## How Nautilus Extensions Work

The extension flow is split by scope:

1. System module enables Nautilus dependencies and integration.
2. Home module scans nautilus-extensions/ for .py files.
3. Each extension script is deployed under XDG data path:
   - ~/.local/share/nautilus-python/extensions/

To add a custom extension:

1. Add a Python file to pkgs/nautilus/nautilus-extensions/.
2. Rebuild and switch.
3. Restart Nautilus.

## Build and Apply

From repository root:

- Dry evaluation:
  - nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run
- Apply system and Home Manager changes through NixOS:
  - sudo nixos-rebuild switch --flake .#<host>

Replace <host> with the configuration name exposed in flake.nix.

## First-Time Setup (Quickstart)

Use this flow on a fresh clone:

```bash
cd /path/to/this/repo

# Check flake outputs and available host names
nix flake show

# Update lock file to latest input revisions (optional)
nix flake update

# Validate evaluation before applying
nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run

# Apply system + Home Manager modules through NixOS
sudo nixos-rebuild switch --flake .#<host>
```

After switching, restart user applications (or log out and back in) to ensure all session-level changes are picked up.

## Common Maintenance Commands

- Update inputs:
  - nix flake update
- Format files:
  - nix fmt
- Show flake outputs:
  - nix flake show

## Design Notes

- Keep Home Manager options out of system modules.
- Keep system options out of Home Manager modules.
- Prefer in-repo paths for managed files when possible.
- Pin external sources by immutable revisions.

## Troubleshooting Checklist

If evaluation fails:

1. Confirm a Home Manager option is not defined in a system module.
2. Confirm the same target file is not defined by multiple modules.
3. Confirm external fetchers are compatible with pure flake evaluation.
4. Run a dry build first and fix errors in order.

## Contributing

When adding a new feature:

1. Decide whether it belongs to system/, home/, or both.
2. Add module(s) under pkgs/<feature>/.
3. Import them from system/default.nix and or home/default.nix.
4. Run dry evaluation before committing changes.
