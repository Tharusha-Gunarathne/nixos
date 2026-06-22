{...}: {
  flake.nixosModules.wlrWhichKey = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;

    mkMenu = {
      name,
      anchor ? "center",
      entries,
    }: let
      configFile = pkgs.writeText "${name}.yaml"
        (lib.generators.toYAML {} {
          inherit anchor;
          font = "JetBrainsMono Nerd Font 12";
          background = "#1e1e2ed0";
          color = "#cdd6f4";
          border = "#89b4fa";
          border_width = 2;
          corner_r = 10;
          padding = 20;
          menu = entries;
        });
    in
      pkgs.writeShellScriptBin name ''
          ${pkgs.coreutils}/bin/timeout 2s ${lib.getExe pkgs.wlr-which-key} ${configFile}
      '';

    wk-apps = mkMenu {
      name = "wk-apps";
      entries = [
        { key = "n"; desc = "Nautilus"; cmd = "nautilus"; }
        { key = "z"; desc = "Zed";      cmd = "zeditor"; }
        { key = "b"; desc = "Brave";    cmd = "brave-default-launcher"; }
        { key = "f"; desc = "Ferdium";  cmd = "ferdium"; }
        { key = "l"; desc = "Lotion";   cmd = "lotion"; }
      ];
    };
  in {
    home-manager.users.${username} = {...}: {
      home.packages = [wk-apps];
    };
  };
}