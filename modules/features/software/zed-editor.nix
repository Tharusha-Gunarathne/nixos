{...}: {
  flake.nixosModules.zed-editor = {
    config,
    ...
  }: let
    username = config.myConfig.primaryUser;
  in {
    home-manager.users.${username} = {
      pkgs,
      ...
    }: {
      programs.zed-editor = {
        enable = true;

        # Extensions to auto-install (use the repo name from github.com/zed-industries/extensions)
        extensions = ["nix" "toml" "rust" "jetbrains-new-ui-icons" "java" "sql" "latex" "php" "rainbow-csv" "git-firefly" "emmet" "emoji-completions" "github-copilot-cli" "live-server"];

        # Extra binaries Zed can find (LSPs, formatters, etc.)
        extraPackages = with pkgs; [
          nixd # Nix LSP
          nixfmt # Nix formatter
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
            light = "JetBrains New UI Icons (Light)";
            dark = "JetBrains New UI Icons (Dark)";
          };

          edit_predictions = {
              mode = "eager"; # "eager" | "subtle" | "disabled"
          };

          cursor_blink = true;
          cursor_shape = "bar"; # "bar" | "block" | "underline" | "hollow"

          terminal = {
            shell = {
              program = "fish";
            };
          };

          ui_font_size = 14;
          buffer_font_size = 14;
          buffer_font_family = "JetBrainsMono Nerd Font";
          vim_mode = true;
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
