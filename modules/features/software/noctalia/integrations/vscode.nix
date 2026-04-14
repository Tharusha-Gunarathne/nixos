{...}: {
  flake.nixosModules.noctaliaVscode = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
    shell = config.myConfig.shell;

    # Keeps VS Code's Noctalia extension path correct after rebuilds.
    fixRegistryScript = pkgs.writers.writePython3 "fix-vscode-registry" {} ''
      import json
      import sys

      registry_path = sys.argv[1]
      correct_path = sys.argv[2]

      with open(registry_path) as f:
          exts = json.load(f)

      for e in exts:
          if e.get("identifier", {}).get("id") == "noctalia.noctaliatheme":
              e["location"] = {
                  "$mid": 1,
                  "fsPath": correct_path,
                  "path": correct_path,
                  "scheme": "file",
              }
              e["relativeLocation"] = correct_path.split("/")[-1]

      with open(registry_path, "w") as f:
          json.dump(exts, f, indent=2)
    '';

    # Removes Noctalia theme key only when it is currently selected.
    cleanupThemeScript = pkgs.writers.writePython3 "cleanup-vscode-noctalia-theme" {} ''
      import json
      import sys

      settings_path = sys.argv[1]

      try:
        with open(settings_path, "r", encoding="utf-8") as f:
          data = json.load(f)
      except Exception:
        sys.exit(0)

      if not isinstance(data, dict):
        sys.exit(0)

      if data.get("workbench.colorTheme") == "NoctaliaTheme":
        data.pop("workbench.colorTheme", None)
        with open(settings_path, "w", encoding="utf-8") as f:
          json.dump(data, f, indent=2)
          f.write("\n")
    '';
  in {
    config = lib.mkMerge [
      (lib.mkIf shell.noctalia {
        home-manager.users.${username} = {
          lib,
          pkgs,
          ...
        }: {
          home.activation.noctaliaVscodeSetup = lib.hm.dag.entryAfter ["writeBoundary" "vscodeSetup"] ''
            EXT_DIR="$HOME/.vscode/extensions"
            EXT_SOURCE="$EXT_DIR/noctalia.noctaliatheme"
            REGISTRY="$EXT_DIR/extensions.json"

            rm -rf "$EXT_DIR/noctalia.noctaliatheme.backup"

            STORE_EXT=$(readlink -f "$EXT_SOURCE" 2>/dev/null || echo "")
            if [ -n "$STORE_EXT" ]; then
              EXT_VERSION=$(${pkgs.python3}/bin/python3 -c \
                "import json; print(json.load(open('$STORE_EXT/package.json'))['version'])" \
                2>/dev/null || echo "0.0.5")
              EXT_VERSIONED="$EXT_DIR/noctalia.noctaliatheme-$EXT_VERSION"

              if [ ! -d "$EXT_VERSIONED" ] || [ -L "$EXT_VERSIONED" ]; then
                rm -rf "$EXT_VERSIONED"
                ${pkgs.coreutils}/bin/cp -r "$STORE_EXT" "$EXT_VERSIONED"
                chmod -R u+w "$EXT_VERSIONED"
              fi

              if [ -f "$REGISTRY" ]; then
                ${fixRegistryScript} "$REGISTRY" "$EXT_VERSIONED"
              fi
            fi
          '';

          programs.vscode.profiles.default.extensions = lib.mkAfter (
            pkgs.nix4vscode.forVscode [
              "noctalia.noctaliatheme"
            ]
          );
        };
      })

      (lib.mkIf (!shell.noctalia) {
        home-manager.users.${username} = {
          lib,
          pkgs,
          ...
        }: {
          home.activation.noctaliaVscodeCleanup = lib.hm.dag.entryAfter ["writeBoundary"] ''
            rm -rf "$HOME/.vscode/extensions/noctalia.noctaliatheme-"*

            SETTINGS="$HOME/.config/Code/User/settings.json"
            if [ -f "$SETTINGS" ]; then
              ${cleanupThemeScript} "$SETTINGS"
            fi
          '';
        };
      })
    ];
  };
}
