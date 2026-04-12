{inputs, ...}: {
  flake.nixosModules.noctaliaVscode = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.username;
    shell = config.myConfig.shell;
  in {
    config = lib.mkIf (shell == "noctalia") {
      home-manager.users.${username} = {
        lib,
        pkgs,
        ...
      }: {
        home.activation.noctaliaVscodeSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
          EXT_SOURCE="$HOME/.vscode/extensions/noctalia.noctaliatheme"
          STORE_EXT=$(readlink -f "$EXT_SOURCE" 2>/dev/null || echo "")
          if [ -n "$STORE_EXT" ]; then
            EXT_VERSION=$(${pkgs.python3}/bin/python3 -c \
              "import json; print(json.load(open('$STORE_EXT/package.json'))['version'])" \
              2>/dev/null || echo "0.0.5")
            EXT_DIR="$HOME/.vscode/extensions/noctalia.noctaliatheme-$EXT_VERSION"
            if [ ! -d "$EXT_DIR" ] || [ -L "$EXT_DIR" ]; then
              rm -rf "$EXT_DIR"
              ${pkgs.coreutils}/bin/cp -r "$STORE_EXT" "$EXT_DIR"
              chmod -R u+w "$EXT_DIR"
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