{...}: {
  flake.nixosModules.noctaliaVscode = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.username;
    shell = config.myConfig.shell;

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
  in {
    config = lib.mkIf (shell == "noctalia") {
      home-manager.users.${username} = {
        lib,
        pkgs,
        ...
      }: {
        home.activation.noctaliaVscodeSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
          EXT_DIR="$HOME/.vscode/extensions"
          EXT_SOURCE="$EXT_DIR/noctalia.noctaliatheme"
          EXT_BACKUP="$EXT_DIR/noctalia.noctaliatheme.backup"
          REGISTRY="$EXT_DIR/extensions.json"

          rm -rf "$EXT_BACKUP"

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
    };
  };
}