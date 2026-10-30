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
        shellAliases.hcodex = "${pkgs.python3}/bin/python3 ${pkgs.lib.escapeShellArg "${config.myConfig.claudeSync.sharedDir}/_sync/codex/agent_launcher.py"} headroom-codex --";
      };

      programs.oh-my-posh = {
        enable = true;
        enableFishIntegration = true;
        useTheme = "hul10"; # or any theme you like
      };
    };
  };
}
