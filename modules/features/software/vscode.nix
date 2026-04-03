{ self, inputs, ... }: {
  flake.nixosModules.vscode = { config, pkgs, ... }:
  let
    username = config.myConfig.username;
    extensions = pkgs.nix4vscode.forVscode [
      # add any extension using "publisher.extension-name" format
      "catppuccin.catppuccin-vsc"
      "catppuccin.catppuccin-vsc-icons"
      "pkief.material-icon-theme"
      "esbenp.prettier-vscode"
      "ms-python.python"
      "mechatroner.rainbow-csv"
      "yzane.markdown-pdf"
      "ritwickdey.liveserver"
      "github.copilot-chat"
      "kdl-org.kdl"
      "bbenoist.nix"
      "jnoortheen.nix-ide"
      "ecmel.vscode-html-css"
    ];
  in {
    nixpkgs.overlays = [ inputs.nix4vscode.overlays.default ];

    home-manager.users.${username} = { ... }: {
      programs.vscode = {
        enable = true;
        profiles.default = {
          extensions = extensions;
          userSettings = {
            "workbench.colorTheme" = "Catppuccin Mocha";
            "workbench.iconTheme" = "catppuccin-mocha";
            "editor.fontFamily" = "JetBrainsMono Nerd Font";
            "editor.fontSize" = 14;
            "editor.fontLigatures" = true;
            "editor.formatOnSave" = true;
            "editor.wordWrap" = "on";
            "files.autoSave" = "afterDelay";
            "files.autoSaveDelay" = 1000;
            "terminal.integrated.fontFamily" = "JetBrainsMono Nerd Font";
          };
        };
      };
    };
  };
}