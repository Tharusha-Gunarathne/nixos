{...}: {
  flake.nixosModules.fastfetch = {
    config,
    lib,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
  in {
    home-manager.users.${username} = {
      config,
      lib,
      pkgs,
      ...
    }: let
      # ${"$"}{1} produces a literal ${1} in the file, which fastfetch
      # replaces with the color defined in logo.color."1"
      c1 = "${"$"}{1}";
      c2 = "${"$"}{2}";

      logoText = ''
        ${c1}███╗   ██╗██╗██╗  ██╗ ██████╗ ███████╗${c2}    ██████╗ ████████╗██╗    ██╗
        ${c1}████╗  ██║██║╚██╗██╔╝██╔═══██╗██╔════╝${c2}    ██╔══██╗╚══██╔══╝██║    ██║
        ${c1}██╔██╗ ██║██║ ╚███╔╝ ██║   ██║███████╗${c2}    ██████╔╝   ██║   ██║ █╗ ██║
        ${c1}██║╚██╗██║██║ ██╔██╗ ██║   ██║╚════██║${c2}    ██╔══██╗   ██║   ██║███╗██║
        ${c1}██║ ╚████║██║██╔╝ ██╗╚██████╔╝███████║${c2}    ██████╔╝   ██║   ╚███╔███╔╝
        ${c1}╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝${c2}    ╚═════╝    ╚═╝    ╚══╝╚══╝ 
      '';

      fastfetchConfig = {
        "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";

        logo = {
          source = "${config.xdg.configHome}/fastfetch/logo.txt";
          color = {
            "1" = "bright_green";
            "2" = "green";
          };
          padding = {
            top = 1;
            right = 4;
          };
        };

        display = {
          separator = " → ";
          color = {
            keys = "green";
            title = "bright_green";
          };
        };

        modules = [
          {type = "Title";}
          {
            type = "Separator";
            string = "─────────────────────────────";
          }
          "OS"
          "Kernel"
          "Packages"
          "Shell"
          {type = "Break";}
          "WM"
          "Theme"
          "Icons"
          "Terminal"
          "Font"
          {type = "Break";}
          {
            type = "Host";
            key = " PC";
          }
          "CPU"
          {
            type = "GPU";
            detectionMethod = "pci";
          }
          {
            type = "Memory";
            key = " RAM";
          }
          {
            type = "Swap";
            key = " Swap";
          }
          {
            type = "Disk";
            key = " Disk";
          }
          "Display"
          {type = "Break";}
          "Uptime"
          {
            type = "DateTime";
            key = " Date";
            format = "%Y-%m-%d";
          }
          "Battery"
          {type = "Break";}
          "Colors"
        ];
      };
    in {
      programs.fastfetch.enable = true;
      
      xdg.configFile."fastfetch/logo.txt".text = logoText;
      xdg.configFile."fastfetch/config.jsonc".text = builtins.toJSON fastfetchConfig;
    };
  };
}
