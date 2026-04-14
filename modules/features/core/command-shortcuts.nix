{...}: {
  flake.nixosModules.commandShortcuts = {pkgs, ...}: {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "nix-switch" ''
        exec sudo nixos-rebuild switch --flake . "$@"
      '')
      (pkgs.writeShellScriptBin "nix-update" ''
        exec sudo nix flake update "$@"
      '')
      (pkgs.writeShellScriptBin "nix-clean" ''
        exec sudo nix-collect-garbage -d "$@"
      '')
    ];
  };
}
