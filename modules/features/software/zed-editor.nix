{...}: {
  flake.nixosModules.zed-editor = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
  in {
    home-manager.users.${username} = {
      pkgs,
      lib,
      ...
    }: {
      programs.zed-editor = {
        enable = true;

        # Extensions to auto-install (use the repo name from github.com/zed-industries/extensions)
        extensions = ["nix" "toml" "rust" "jetbrains-new-ui-icons" "java" "sql" "latex" "php" "rainbow-csv" "git-firefly" "emmet" "emoji-completions"];

        # Extra binaries Zed can find (LSPs, formatters, etc.)
        extraPackages = with pkgs; [
          nixd # Nix LSP
          nixfmt-rfc-style
          rust-analyzer
        ];

        userSettings = {
          theme = {
            mode = "system";
            dark = "Ayu Dark";
            light = "One Light";
          };
          icon_theme = {
            mode = "system";
            light = "jetbrains-new-ui-icons";
            dark = "jetbrains-new-ui-icons";
          };

          cursor_blink = true;
          cursor_shape = "bar"; # "bar" | "block" | "underline" | "hollow"
          cursor_trail_length = 12;

          terminal = {
            shell = {
              program = "fish";
            };
          };

          ui_font_size = 14;
          buffer_font_size = 14;
          buffer_font_family = "JetBrains Mono";
          vim_mode = true;
          hour_format = "hour24";
          format_on_save = "on";

          languages = {
            Nix = {
              language_servers = ["nixd" "!nil"];
              formatter = {
                external = {
                  command = "nixfmt";
                };
              };
            };
          };

          lsp = {
            nixd = {
              settings = {
                nixpkgs = {
                  expr = "import <nixpkgs> {}";
                };
              };
            };
          };
        };
      };
    };
  };
}
