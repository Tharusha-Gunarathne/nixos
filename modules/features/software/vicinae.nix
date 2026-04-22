{inputs, ...}: {
  flake.nixosModules.vicinae = {config, ...}: let
    username = config.myConfig.primaryUser;
    shell = config.myConfig.shell;
  in {
    home-manager.users.${username} = {...}: {
      imports = [inputs.vicinae.homeManagerModules.default];

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
          launcher_window = {
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
            dark.name =
              if shell.noctalia
              then "noctalia"
              else "dark";
            light.name =
              if shell.noctalia
              then "noctalia"
              else "light";
          };
          font = {
            normal = {
              family = "Ubuntu Sans";
              size = 10.5;
            };
          };
        };
      };
    };
  };
}
