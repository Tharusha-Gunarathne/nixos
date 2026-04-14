{...}: {
  flake.nixosModules.fish = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
  in {
    # enables vendor completions from nixpkgs packages
    programs.fish.enable = true;

    home-manager.users.${username} = {pkgs, ...}: {
      programs.fish = {
        enable = true;
        interactiveShellInit = "set fish_greeting";
        shellAliases = {
          nix-switch = "sudo nixos-rebuild switch --flake .";
          nix-update = "sudo nix flake update";
          nix-clean = "sudo nix-collect-garbage -d";
        };
      };

      programs.oh-my-posh = {
        enable = true;
        enableFishIntegration = true;
        useTheme = "montys"; # or any theme you like
      };
    };
  };
}
