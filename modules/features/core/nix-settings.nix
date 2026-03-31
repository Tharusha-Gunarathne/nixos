{ self, ... }: {
  flake.nixosModules.nixSettings = { ... }: {
    nixpkgs.config.allowUnfree = true;
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    system.stateVersion = "25.11";
  };

  perSystem = { pkgs, ... }: {
    formatter = pkgs.alejandra;
  };
}
