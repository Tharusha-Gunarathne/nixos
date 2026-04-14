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

      WALLCARDS="$out/WallcardsWindow.qml"
      WALLCARDS_MANIFEST="$out/manifest.json"

      ${pkgs.perl}/bin/perl -0777 -i -pe 's@import Qt5Compat\.GraphicalEffects\n@@g' "$WALLCARDS"

      ${pkgs.perl}/bin/perl -0777 -i -pe 's@\n            Rectangle \{\n              id: mask\n\n              anchors.fill: parent\n              radius: cardRadius\n              visible: false\n            \}\n\n            OpacityMask \{\n              anchors.fill: parent\n              maskSource: mask\n\n              source: ShaderEffectSource \{\n                sourceItem: imgComposite\n                sourceRect: Qt\.rect\(-imgComposite\.x, 0, imageFrame\.width, imageFrame\.height\)\n              \}\n            \}\n@\n            ShaderEffectSource {\n              anchors.fill: parent\n              sourceItem: imgComposite\n              sourceRect: Qt.rect(-imgComposite.x, 0, imageFrame.width, imageFrame.height)\n            }\n@s' "$WALLCARDS"

      ${pkgs.perl}/bin/perl -0777 -i -pe 's@\n                  layer\.effect: OpacityMask \{\n                    maskSource: Rectangle \{\n                      width: videoContainer\.width\n                      height: videoContainer\.height\n                      radius: cardRadius\n                    \}\n                  \}\n@\n                  layer.effect: null\n@s' "$WALLCARDS"

      # Hide filename/extension badges on cards.
      ${pkgs.gnused}/bin/sed -i '/visible: cardDelegate.currentFileName !== ""/s@.*@              visible: false@' "$WALLCARDS"
      ${pkgs.gnused}/bin/sed -i '/text: cardDelegate.currentFileName.split/s@.*@              text: ""@' "$WALLCARDS"
      ${pkgs.gnused}/bin/sed -i 's@visible: isCenter@visible: false@' "$WALLCARDS"
      ${pkgs.gnused}/bin/sed -i '/text: cardDelegate.currentFileName.substring/s@.*@              text: ""@' "$WALLCARDS"

      # Adjust wallcards defaults: slightly larger than stock, more centered, no radius mismatch,
      # and a subtle background dim.
      ${pkgs.perl}/bin/perl -0777 -i -pe 's/"card_height"\s*:\s*500/"card_height": 540/g; s/"card_strip_width"\s*:\s*80/"card_strip_width": 92/g; s/"card_radius"\s*:\s*10/"card_radius": 0/g; s/"background_opacity"\s*:\s*null/"background_opacity": 0.3/g' "$WALLCARDS_MANIFEST"

      if ${pkgs.gnugrep}/bin/grep -qE 'Qt5Compat\.GraphicalEffects|OpacityMask' "$WALLCARDS"; then
        echo "[wallcards-patched] patch did not fully apply" >&2
        exit 1
      fi
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
