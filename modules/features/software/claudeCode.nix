{inputs, ...}: {
  flake.nixosModules.claudeCode = {
    config,
    ...
  }: let
    username = config.myConfig.primaryUser;
    home = config.home-manager.users.${username}.home.homeDirectory or "/home/${username}";
    claude = inputs.claude-plugins.inputs;
  in {
    home-manager.users.${username} = {...}: {
      home.file = {
        "${home}/.claude/skills/caveman".source = "${claude.caveman-skill}/skills/caveman";
        "${home}/.claude/skills/caveman-commit".source = "${claude.caveman-skill}/skills/caveman-commit";
        "${home}/.claude/skills/caveman-compress".source = "${claude.caveman-skill}/skills/caveman-compress";
        "${home}/.claude/skills/caveman-help".source = "${claude.caveman-skill}/skills/caveman-help";
        "${home}/.claude/skills/caveman-review".source = "${claude.caveman-skill}/skills/caveman-review";
        "${home}/.claude/skills/caveman-stats".source = "${claude.caveman-skill}/skills/caveman-stats";
        "${home}/.claude/skills/cavecrew".source = "${claude.caveman-skill}/skills/cavecrew";

        "${home}/.claude/skills/taste-skill".source = "${claude.taste-skill}/skills/taste-skill";

        "${home}/.claude/skills/hallmark".source = "${claude.hallmark-skill}/skills/hallmark";
      };
    };
  };
}
 