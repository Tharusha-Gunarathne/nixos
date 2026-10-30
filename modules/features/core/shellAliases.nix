{inputs, ...}: {
  flake.nixosModules.shellAliases = {
    pkgs,
    config,
    lib,
    ...
  }: let
    home = config.home-manager.users.${config.myConfig.primaryUser};
    cachedDesktopPackages = lib.unique (
      [config.programs.niri.package]
      ++ lib.optionals config.services.displayManager.noctalia-greeter.enable [config.services.displayManager.noctalia-greeter.package]
      ++ lib.optionals (home.programs.noctalia.enable or false) [home.programs.noctalia.package]
      ++ lib.optionals (home.programs.vicinae.enable or false) [home.programs.vicinae.package]
      ++ map (package: package.desktopCacheBase)
        (builtins.filter (package: package ? desktopCacheBase) home.home.packages)
    );
    rebuild = pkgs.writeShellScript "nix-switch-rebuild" ''
      # Transient system services do not inherit the interactive shell's PATH.
      export PATH="${pkgs.lib.makeBinPath [pkgs.git pkgs.nix pkgs.coreutils]}:/run/current-system/sw/bin"
      cd "${config.myConfig.repoRoot}" || exit 1
      export NIXOS_LOCAL_CONFIG="$PWD/.env.local"
      # systemd-run drops sudo's caller context. libgit2 uses SUDO_UID to
      # accept the original user's checkout when evaluating as root.
      export SUDO_UID=${toString config.myConfig.primaryUid}

      cache_root="$(mktemp -d -t nix-switch.XXXXXX)" || exit 1
      was_up=0
      cleanup() {
        if [ "$was_up" -eq 1 ]; then
          echo "Restoring Tailscale..."
          ${pkgs.tailscale}/bin/tailscale up
        fi
        rm -rf -- "$cache_root"
      }
      trap cleanup EXIT

      allow_source_builds=0
      rebuild_args=()
      for arg in "$@"; do
        case "$arg" in
          --allow-source-builds) allow_source_builds=1 ;;
          *) rebuild_args+=("$arg") ;;
        esac
      done

      if [ "$allow_source_builds" -eq 0 ]; then
        echo "Evaluating desktop cache targets from the current configuration..."
        if ! nix eval --impure --raw '.#nixosConfigurations.nixos.config.myConfig.rebuild.cachePackages' \
          --apply 'packages: builtins.concatStringsSep "\n" (map toString packages)' \
          > "$cache_root/targets"; then
          echo "Could not evaluate the configuration; no services were changed." >&2
          exit 1
        fi
        mapfile -t cache_targets < "$cache_root/targets"
        if [ "''${#cache_targets[@]}" -eq 0 ]; then
          echo "No desktop cache targets were returned." >&2
          exit 1
        fi
        echo "Checking cached desktop packages, including Niri and the greeter..."
        if ! nix-store --realise --max-jobs 0 --add-root "$cache_root/desktop" --indirect "''${cache_targets[@]}"; then
          echo "A desktop binary cache is unavailable. Stopping before a large local compilation." >&2
          echo "Retry later, or explicitly permit compilation with nix-switch --allow-source-builds." >&2
          exit 1
        fi
      fi

      if ${pkgs.tailscale}/bin/tailscale status --json | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' >/dev/null 2>&1; then
        was_up=1
        echo "Bringing Tailscale down for the rebuild..."
        ${pkgs.tailscale}/bin/tailscale down || exit 1
      fi

      # Apply limits immediately, including before this config is activated.
      if /run/current-system/sw/bin/nixos-rebuild switch --impure --flake ".#nixos" \
        --max-jobs 2 --cores 2 --option keep-going false \
        --option min-free ${toString config.nix.settings.min-free} \
        --option max-free ${toString config.nix.settings.max-free} "''${rebuild_args[@]}"; then
        echo "Switch completed. Scheduling background GC; rollback generations are retained."
        if ! ${pkgs.systemd}/bin/systemd-run --unit=nix-switch-gc --collect --service-type=exec \
          --description="Collect unreferenced Nix build data after a successful switch" \
          --property=Nice=19 --property=IOSchedulingClass=idle \
          ${pkgs.nix}/bin/nix-store --gc; then
          echo "Background GC was not started (it may already be running); the switch succeeded." >&2
        fi
      else
        exit "$?"
      fi
    '';
  in {
    options.myConfig.rebuild.cachePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      internal = true;
      readOnly = true;
      description = "Expensive desktop packages checked before a rebuild, excluding small local launchers.";
    };

    config = {
      myConfig.rebuild.cachePackages = cachedDesktopPackages;
      environment.systemPackages = [
        # Nix management shortcuts (always operate from repo root)
        (pkgs.writeShellScriptBin "nix-switch" ''
          case "''${1:-}" in
            --logs)
              shift
              exec ${pkgs.systemd}/bin/journalctl -fu nix-switch.service "$@"
              ;;
            --status)
              if ${pkgs.systemd}/bin/systemctl is-active --quiet nix-switch.service; then
                exec ${pkgs.systemd}/bin/systemctl status nix-switch.service --no-pager
              fi
              exec ${pkgs.systemd}/bin/journalctl -u nix-switch.service -n 20 --no-pager
              ;;
            --plan)
              shift
              cd "${config.myConfig.repoRoot}" || exit 1
              export NIXOS_LOCAL_CONFIG="$PWD/.env.local"
              exec ${pkgs.nix}/bin/nix build '.#nixosConfigurations.nixos.config.system.build.toplevel' --impure --no-link --dry-run "$@"
              ;;
            --help|-h)
              echo "Usage: nix-switch [nixos-rebuild flags] [--allow-source-builds]"
              echo "       nix-switch --plan | --status | --logs"
              echo "Rebuilds run as a system service and survive terminal hangups."
              echo "Desktop binary-cache misses stop the rebuild unless explicitly allowed."
              exit 0
              ;;
          esac
          if ${pkgs.systemd}/bin/systemctl is-active --quiet nix-switch.service; then
            echo "A switch is already running. Use nix-switch --logs or --status." >&2
            exit 1
          fi
          echo "Rebuilding as nix-switch.service (continues if this terminal disconnects)."
          echo "Watch progress: nix-switch --logs"
          echo "Check the result: nix-switch --status"
          exec sudo ${pkgs.systemd}/bin/systemd-run \
            --unit=nix-switch --collect --service-type=exec \
            --description="NixOS configuration rebuild" \
            ${rebuild} "$@"
        '')
        (pkgs.writeShellScriptBin "nix-update" ''
          REPO_ROOT="${config.myConfig.repoRoot}"
          cd "$REPO_ROOT"
          exec nix flake update "$@"
        '')
        (pkgs.writeShellScriptBin "nix-clean" ''
          # Preserve rollback generations unless deletion is explicitly requested.
          exec sudo nix-collect-garbage "$@"
        '')
        (pkgs.writeShellScriptBin "qs" ''
          exec noctalia-shell "$@"
        '')
        # ----------------------------

        (pkgs.writeShellScriptBin "handbrake" ''
          exec fr.handbrake.ghb "$@"
        '')

        # To open desktop entries
        (pkgs.writeShellScriptBin "open" ''
          exec ${pkgs.glib}/bin/gio launch "$@"
        '')

        # Free Claude Code
        # (pkgs.writeShellScriptBin "start-free-claude-code" ''
        #   exec systemctl --user start free-claude-code "$@"
        # '')
        # (pkgs.writeShellScriptBin "stop-free-claude-code" ''
        #   exec systemctl --user stop free-claude-code "$@"
        # '')
        # (pkgs.writeShellScriptBin "restart-free-claude-code" ''
        #   exec systemctl --user restart free-claude-code "$@"
        # '')
        # (pkgs.writeShellScriptBin "status-free-claude-code" ''
        #   exec systemctl --user status free-claude-code "$@"
        # '')
        # ----------------------------

      ];
    };
  };
}
