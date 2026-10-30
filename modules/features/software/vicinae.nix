{inputs, ...}: {
  flake.nixosModules.vicinae = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    shell = config.myConfig.shell;
    vicinaePackage = inputs.vicinae.vicinae-main.packages.${pkgs.stdenv.hostPlatform.system}.default;
  in {
    environment.systemPackages = with pkgs; [
      cliphist  # clipboard history backend used by Noctalia and Vicinae
    ];

    # Vicinae v0.20.3+ uses uinput for paste support instead of wtype.
    # It hardcodes /run/wrappers/bin/vicinae-input-server as the binary path,
    # so a setuid wrapper must be created at exactly that location.
    security.wrappers.vicinae-input-server = {
      source = "${vicinaePackage}/libexec/vicinae/vicinae-input-server";
      owner = "root";
      group = "root";
      permissions = "a+rx";
      setuid = false;
      setgid = false;
    };

    home-manager.users.${username} = {pkgs, ...}: {
      imports = [inputs.vicinae.vicinae-main.homeManagerModules.default];

      systemd.user.services.vicinae.Service.UnsetEnvironment = ["LD_LIBRARY_PATH"];
      programs.vicinae = {
        enable = true;
        package = vicinaePackage;
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
