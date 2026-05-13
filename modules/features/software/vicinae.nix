{inputs, ...}: {
  flake.nixosModules.vicinae = {config, ...}: let
    username = config.myConfig.primaryUser;
    shell = config.myConfig.shell;
  in {
    home-manager.users.${username} = {pkgs, ...}: {
      imports = [inputs.vicinae.vicinae-main.homeManagerModules.default];

      services.vicinae = {
        enable = true;
        systemd = {
          enable = true;
          autoStart = true;
          environment = {
            USE_LAYER_SHELL = 1;
          };
        };
        settings = {
          close_on_focus_loss = true;
          activate_on_single_click = true;
          launcher_window = {
            opacity = 0.95;
            layer_shell = {
              keyboard_interactivity = "on_demand";
            };
          };
          providers = {
            applications = {
              preferences = {
                defaultAction = "launch";
              };
            };
            clipboard = {
              entrypoints = {
                history = {
                  preferences = {
                    defaultAction = "paste";
                  };
                };
              };
            };
          };
          theme = {
            dark = {
              name =
                if shell.noctalia
                then "noctalia"
                else "dark";
              icon_theme = "Papirus-Dark";
            };
            light = {
              name =
                if shell.noctalia
                then "noctalia"
                else "light";
              icon_theme = "Papirus-Light";
            };
          };
          font = {
            normal = {
              family = "Ubuntu Sans";
              size = 10.5;
            };
          };
          extensions = let
            exts = inputs.vicinae.vicinae-extensions.packages.${pkgs.stdenv.hostPlatform.system};
          in [
            exts.bluetooth
            exts.nix
            exts.power-profile
            exts.process-manager
            exts.noctalia-shell-wallpaper-selector
            exts.fuzzy-files
            exts.it-tools
            exts.niri
            exts.port-killer
            exts.brotab
            exts.vscode-recents
            exts.zed-recents
            exts.chromium-bookmarks
          ];
        };
      };
    };
  };
}
