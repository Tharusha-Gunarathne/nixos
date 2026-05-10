{...}: {
  flake.nixosModules.nixSettings = {config, ...}: {
    nix.settings.trusted-users = ["root" config.myConfig.primaryUser];
    nixpkgs.config.allowUnfree = true;
    nix.settings.experimental-features = ["nix-command" "flakes"];
    # Optional secret file for API tokens (kept out of git).
    # Expected format, for example:
    # access-tokens = github.com=ghp_xxx
    nix.extraOptions = ''
      !include /etc/nix/access-tokens.conf
    '';
    system.stateVersion = "25.11";
  };

  perSystem = {pkgs, ...}: {
    formatter = pkgs.alejandra;
  };
}
