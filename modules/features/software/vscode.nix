{inputs, ...}: {
  flake.nixosModules.vscode = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.username;
    extensions =
      pkgs.nix4vscode.forVscode [
        "pkief.material-icon-theme"
        "esbenp.prettier-vscode"
        "mechatroner.rainbow-csv"
        "yzane.markdown-pdf"
        "ritwickdey.liveserver"
        "kdl-org.kdl"
        "bbenoist.nix"
        "jnoortheen.nix-ide"
        "ecmel.vscode-html-css"
      ]
      ++ (with pkgs.vscode-extensions; [
        github.copilot
        github.copilot-chat
        ms-python.python
        ms-python.debugpy
        ms-vscode.cpptools
        ms-vscode.cpptools-extension-pack
        bmewburn.vscode-intelephense-client
        jdinhlife.gruvbox
      ]);

    vscodeSettings = {
      "workbench.iconTheme" = "material-icon-theme";
      "editor.fontFamily" = "JetBrainsMono Nerd Font";
      "editor.fontSize" = 14;
      "editor.fontLigatures" = true;
      "editor.formatOnSave" = true;
      "editor.wordWrap" = "on";
      "files.autoSave" = "afterDelay";
      "files.autoSaveDelay" = 1000;
      "terminal.integrated.fontFamily" = "JetBrainsMono Nerd Font";
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "terminal.integrated.defaultProfile.linux" = "fish";
      "terminal.integrated.profiles.linux" = {
        "fish" = {
          "path" = "${pkgs.fish}/bin/fish";
        };
      };
      "markdown-pdf.executablePath" = "${pkgs.brave}/bin/brave";
      "python.defaultInterpreterPath" = "${pkgs.python3}/bin/python";
      "php.validate.enable" = false;
      "php.suggest.basic" = false;
      "[nix]" = {
        "editor.defaultFormatter" = "jnoortheen.nix-ide";
      };
      "nix.formatterPath" = "${pkgs.alejandra}/bin/alejandra";
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "${pkgs.nil}/bin/nil";
      "nix.serverSettings" = {
        "nil" = {
          "formatting" = {
            "command" = ["${pkgs.alejandra}/bin/alejandra"];
          };
        };
      };
    };

    settingsJson = pkgs.writeText "vscode-settings.json"
      (builtins.toJSON vscodeSettings);
  in {
    nixpkgs.overlays = [inputs.nix4vscode.overlays.default];

    home-manager.users.${username} = {
      lib,
      pkgs,
      ...
    }: {
      home.activation.vscodeSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
        SETTINGS_DIR="$HOME/.config/Code/User"
        SETTINGS="$SETTINGS_DIR/settings.json"
        BACKUP="$SETTINGS_DIR/settings.json.backup"

        rm -f "$BACKUP"

        if [ ! -f "$SETTINGS" ] || [ -L "$SETTINGS" ]; then
          mkdir -p "$SETTINGS_DIR"
          rm -f "$SETTINGS"
          ${pkgs.coreutils}/bin/install -m 644 ${settingsJson} "$SETTINGS"
        fi
      '';

      programs.vscode = {
        enable = true;
        profiles.default = {
          extensions = extensions;
        };
      };
    };
  };
}