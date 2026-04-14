{inputs, ...}: {
  flake.nixosModules.noctaliaPluginSettings = {
    config,
    lib,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    shell = config.myConfig.shell;

    wallcardsPatched = pkgs.runCommand "wallcards-patched" {} ''
          cp -r "${inputs.noctalia.plugins.wallcards}" "$out"
          chmod -R u+w "$out"

          ${pkgs.gnused}/bin/sed -i '/^import Qt5Compat\.GraphicalEffects$/d' "$out/WallcardsWindow.qml"

          ${pkgs.gnused}/bin/sed -i '/^            Rectangle {$/,/^            }$/ {
            /^            Rectangle {$/,/^            }$/ {
              /^              id: mask$/,/^            }$/d
            }
          }' "$out/WallcardsWindow.qml"

          ${pkgs.gnused}/bin/sed -i '/^            OpacityMask {$/,/^            }$/d' "$out/WallcardsWindow.qml"

          ${pkgs.gnused}/bin/sed -i '/^                  layer\.effect: OpacityMask {$/,/^                  }$/c\
                          layer.effect: null' "$out/WallcardsWindow.qml"

          ${pkgs.gnused}/bin/sed -i '/^            \/\/ ── Video type ──$/i\
            ShaderEffectSource {\
              anchors.fill: parent\
              sourceItem: imgComposite\
              sourceRect: Qt.rect(-imgComposite.x, 0, imageFrame.width, imageFrame.height)\
            }\
      ' "$out/WallcardsWindow.qml"
    '';

    pluginSettings =
      (builtins.listToAttrs (map (name: {
        name = "noctalia/plugins/${name}";
        value = {source = inputs.noctalia.plugins.${name};};
      }) (builtins.attrNames inputs.noctalia.plugins)))
      // {
        "noctalia/plugins/wallcards" = {
          source = wallcardsPatched;
        };
      };
  in {
    config = lib.mkIf shell.noctalia {
      home-manager.users.${username} = {...}: {
        xdg.configFile = pluginSettings;
      };
    };
  };
}
