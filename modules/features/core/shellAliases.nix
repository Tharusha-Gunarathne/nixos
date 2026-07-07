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
        exec sudo nixos-rebuild switch --flake "path:.#nixos" "$@"
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
