{...}: {
  flake.nixosModules.shellAliases = {
    pkgs,
    config,
    ...
  }: {
    environment.systemPackages = [
      # Nix management shortcuts (always operate from repo root)
      (pkgs.writeShellScriptBin "nix-switch" ''
        REPO_ROOT="${config.myConfig.repoRoot}"
        cd "$REPO_ROOT"

        was_up=0
        if ${pkgs.tailscale}/bin/tailscale status --json | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' >/dev/null 2>&1; then
          was_up=1
          echo "Bringing Tailscale down for the rebuild..."
          sudo ${pkgs.tailscale}/bin/tailscale down
        fi

        restore_tailscale() {
          if [ "$was_up" -eq 1 ]; then
            echo "Restoring Tailscale..."
            sudo ${pkgs.tailscale}/bin/tailscale up
          fi
        }
        trap restore_tailscale EXIT

        sudo nixos-rebuild switch --flake "path:.#nixos" "$@"
      '')
      (pkgs.writeShellScriptBin "nix-update" ''
        REPO_ROOT="${config.myConfig.repoRoot}"
        cd "$REPO_ROOT"
        exec nix flake update "$@"
      '')
      (pkgs.writeShellScriptBin "nix-clean" ''
        exec sudo nix-collect-garbage -d "$@"
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

      # LifeOS launcher
      (pkgs.writeShellScriptBin "lifeos" ''
        exec bun "$HOME/.claude/LIFEOS/TOOLS/lifeos.ts" -s "$HOME/.claude/LIFEOS/LIFEOS_SYSTEM_PROMPT.md" "$@"
      '')
      # ----------------------------

      # Open-Web-UI
      (pkgs.writeShellScriptBin "start-open-web-ui" ''
        exec systemctl --user start open-webui "$@"
      '')
      (pkgs.writeShellScriptBin "stop-open-web-ui" ''
        exec systemctl --user stop open-webui "$@"
      '')
      (pkgs.writeShellScriptBin "restart-open-web-ui" ''
        exec systemctl --user restart open-webui "$@"
      '')
      (pkgs.writeShellScriptBin "status-open-web-ui" ''
        exec systemctl --user status open-webui "$@"
      '')
      # ----------------------------
    ];
  };
}
