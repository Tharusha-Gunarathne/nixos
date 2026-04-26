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
      };

      programs.oh-my-posh = {
        enable = true;
        enableFishIntegration = true;
        useTheme = "hul10"; # or any theme you like
      };
    };
  };
}
