{...}: {
  flake.nixosModules.shellAliases = {pkgs, ...}: {
    environment.systemPackages = [
      # Nix management shortcuts
      (pkgs.writeShellScriptBin "nix-switch" ''
        exec sudo nixos-rebuild switch --flake . "$@"
      '')
      (pkgs.writeShellScriptBin "nix-update" ''
        exec sudo nix flake update "$@"
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
      (pkgs.writeShellScriptBin "start-free-claude-code" ''
        exec systemctl --user start free-claude-code "$@"
      '')
      (pkgs.writeShellScriptBin "stop-free-claude-code" ''
        exec systemctl --user stop free-claude-code "$@"
      '')
      (pkgs.writeShellScriptBin "restart-free-claude-code" ''
        exec systemctl --user restart free-claude-code "$@"
      '')
      (pkgs.writeShellScriptBin "status-free-claude-code" ''
        exec systemctl --user status free-claude-code "$@"
      '')
      # ----------------------------
    ];
  };
}
