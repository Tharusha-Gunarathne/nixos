{...}: {
  flake.nixosModules.nixSettings = {config, ...}: {
    nix.settings.trusted-users = ["root" config.myConfig.primaryUser];
    nixpkgs.config.allowUnfree = true;
    nix.settings.experimental-features = ["nix-command" "flakes"];
    system.stateVersion = "25.11";
  };

  perSystem = {pkgs, ...}: {
    formatter = pkgs.alejandra;
  };
}