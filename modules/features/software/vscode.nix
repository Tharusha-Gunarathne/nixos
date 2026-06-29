{inputs, ...}: {
  flake.nixosModules.vscode = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;

    extensions =
      pkgs.nix4vscode.forVscode [
        "pkief.material-icon-theme"
        "esbenp.prettier-vscode"
        "mechatroner.rainbow-csv"
        "yzane.markdown-pdf"
        "ritwickdey.liveserver"
        "kdl-org.kdl"
        "jnoortheen.nix-ide"
        "ecmel.vscode-html-css"
        "anthropic.claude-code"
        "tomoki1207.pdf"
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
      "terminal.integrated.defaultProfile.linux" = "fish";
      "terminal.integrated.profiles.linux" = {
        "fish" = {
          "path" = "/etc/profiles/per-user/${username}/bin/fish";
        };
      };
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
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

    settingsJson =
      pkgs.writeText "vscode-settings.json"
      (builtins.toJSON vscodeSettings);

    mergeSettingsScript =
      pkgs.writers.writePython3 "merge-vscode-settings" {
        libraries = [pkgs.python3Packages.json5];
      } ''
        import json
        import json5
        import os
        import sys

        settings_path = sys.argv[1]
        defaults_path = sys.argv[2]

        with open(defaults_path, "r", encoding="utf-8") as f:
            defaults = json.load(f)

        try:
            with open(settings_path, "r", encoding="utf-8") as f:
                current = json5.load(f)
        except Exception:
            current = {}

        if not isinstance(current, dict):
            current = {}


        def merge_missing(dst, src):
            for key, value in src.items():
                if key not in dst:
                    dst[key] = value
                elif isinstance(dst[key], dict) and isinstance(value, dict):
                    merge_missing(dst[key], value)


        merge_missing(current, defaults)

        # Always enforce these keys so they stay correct after every rebuild
        managed_keys = [
            "[nix]",
            "nix.formatterPath",
            "nix.enableLanguageServer",
            "nix.serverPath",
            "nix.serverSettings",
            "terminal.integrated.defaultProfile.linux",
            "terminal.integrated.profiles.linux",
            "markdown-pdf.executablePath",
        ]
        for key in managed_keys:
            current[key] = defaults[key]

        # Atomic write
        tmp_path = settings_path + ".tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(current, f, indent=2)
            f.write("\n")
        os.replace(tmp_path, settings_path)
      '';
  in {
    nixpkgs.overlays = [inputs.nix4vscode.overlays.default];

    home-manager.users.${username} = {
      lib,
      pkgs,
      ...
    }: {
      xdg.configFile."Code/User/settings.json".enable = false;

      home.activation.vscodeSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
        SETTINGS_DIR="$HOME/.config/Code/User"
        SETTINGS="$SETTINGS_DIR/settings.json"

        mkdir -p "$SETTINGS_DIR"
        rm -f "$SETTINGS.backup"

        # If file doesn't exist or is still a store symlink, seed from scratch
        if [ ! -f "$SETTINGS" ] || [ -L "$SETTINGS" ]; then
          rm -f "$SETTINGS"
          ${pkgs.coreutils}/bin/install -m 644 ${settingsJson} "$SETTINGS"
        fi

        # Always merge base settings into the writable file.
        # Preserves user values (including theme) while enforcing managed keys.
        ${mergeSettingsScript} "$SETTINGS" "${settingsJson}"
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