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

      if [ -f "$out/Wallcards.qml" ]; then
        WALLCARDS="$out/Wallcards.qml"
      elif [ -f "$out/WallcardsWindow.qml" ]; then
        WALLCARDS="$out/WallcardsWindow.qml"
      else
        echo "[wallcards-patched] could not find Wallcards.qml or WallcardsWindow.qml" >&2
        exit 1
      fi
      CARD_QML="$out/src/Card.qml"
      if [ ! -f "$CARD_QML" ] && [ -f "$out/Card.qml" ]; then
        CARD_QML="$out/Card.qml"
      fi
      if [ ! -f "$CARD_QML" ]; then
        echo "[wallcards-patched] could not find Card.qml" >&2
        exit 1
      fi
      WALLCARDS_MANIFEST="$out/manifest.json"

      ${pkgs.perl}/bin/perl -0777 -i -pe 's@import Qt5Compat\.GraphicalEffects\n@@g' "$WALLCARDS" "$CARD_QML"

      ${pkgs.perl}/bin/perl -0777 -i -pe 's@\n  Rectangle \{\n    id: mask\n\n    anchors.fill: parent\n    radius: cardContent.radius\n    visible: false\n  \}\n\n  OpacityMask \{\n    anchors.fill: parent\n    maskSource: mask\n\n    source: ShaderEffectSource \{\n      sourceItem: imgComposite\n      sourceRect: Qt\.rect\(-imgComposite\.x, 0, cardContent\.width, cardContent\.height\)\n    \}\n  \}\n@\n  ShaderEffectSource {\n    anchors.fill: parent\n    sourceItem: imgComposite\n    sourceRect: Qt.rect(-imgComposite.x, 0, cardContent.width, cardContent.height)\n  }\n@s' "$CARD_QML"

      ${pkgs.perl}/bin/perl -0777 -i -pe 's@\n        layer\.effect: OpacityMask \{\n          maskSource: Rectangle \{\n            height: videoContainer\.height\n            radius: cardContent\.radius\n            width: videoContainer\.width\n          \}\n        \}\n@\n        layer.effect: null\n@s' "$CARD_QML"

      ${pkgs.perl}/bin/perl -0777 -i -pe 's/"card_height"\s*:\s*(?:500|350)/"card_height": 390/g; s/"card_strip_width"\s*:\s*(?:80|90)/"card_strip_width": 102/g; s/"card_radius"\s*:\s*10/"card_radius": 0/g; s/"background_opacity"\s*:\s*null/"background_opacity": 0.3/g' "$WALLCARDS_MANIFEST"

      if ${pkgs.gnugrep}/bin/grep -qE 'Qt5Compat\.GraphicalEffects|OpacityMask' "$WALLCARDS" "$CARD_QML"; then
        echo "[wallcards-patched] patch did not fully apply" >&2
        exit 1
      fi
    '';
  in {
    config = lib.mkIf shell.noctalia {
      home-manager.users.${username} = {...}: {
        xdg.configFile =
          (builtins.listToAttrs (map (name: {
            name = "noctalia/plugins/${name}";
            value = {source = inputs.noctalia.plugins.${name};};
          }) (builtins.attrNames inputs.noctalia.plugins)))
          // {
            "noctalia/plugins/wallcards" = {
              source = wallcardsPatched;
            };
          };
      };
    };
  };
}
