{ inputs, ... }: {
  flake.nixosModules.discord = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    nixcordModule = inputs.nixcord.homeModules.nixcord;

    vesktopSettingsFallback = pkgs.writeText "vesktop-settings.json" (builtins.toJSON {
      discordBranch = "stable";
      minimizeToTray = false;
      arRPC = true;
      splashColor = "rgb(196, 198, 208)";
      splashBackground = "rgb(18, 19, 22)";
    });

    patchMinimizeToTray = pkgs.writers.writePython3 "patch-vesktop-settings" {} ''
      import json
      import sys

      settings_path = sys.argv[1]
      with open(settings_path, "r") as f:
          data = json.load(f)

      data["minimizeToTray"] = False

      with open(settings_path, "w") as f:
          json.dump(data, f, indent=2)
    '';
    selectVencord = pkgs.writers.writePython3 "select-vesktop-vencord" {} ''
      import json
      import os
      from pathlib import Path
      import shutil
      import sys
      import tempfile

      state = Path(sys.argv[1])
      vencord = Path(sys.argv[2])
      if not (vencord / "vencordDesktopMain.js").is_file():
          raise SystemExit("Packaged Vencord is missing its desktop entry point")
      data = json.loads(state.read_text()) if state.exists() else {}
      if not isinstance(data, dict):
          raise SystemExit(
              "Vesktop state must be a JSON object; leaving it untouched"
          )
      previous = data.get("vencordDir")
      # Preserve a user-selected custom build outside the Nix store.
      if previous and not str(previous).startswith("/nix/store/"):
          raise SystemExit(0)
      if previous == str(vencord):
          raise SystemExit(0)
      state.parent.mkdir(parents=True, exist_ok=True)
      backup = state.with_name(state.name + ".before-cache-migration")
      if state.exists() and not backup.exists():
          shutil.copyfile(state, backup)
          backup.chmod(0o600)
      data["vencordDir"] = str(vencord)
      with tempfile.NamedTemporaryFile(
          mode="w", dir=state.parent, delete=False
      ) as f:
          temp = Path(f.name)
          json.dump(data, f, indent=2)
      try:
          os.replace(temp, state)
      finally:
          temp.unlink(missing_ok=True)
    '';
    mkCachedVesktop = vencord: pkgs.symlinkJoin {
      name = "vesktop-${pkgs.vesktop.version}-cache-friendly";
      inherit (pkgs.vesktop) meta;
      paths = [pkgs.vesktop];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        rm "$out/bin/vesktop"
        makeWrapper ${pkgs.vesktop}/bin/vesktop "$out/bin/vesktop" \
          --run '${selectVencord} "$HOME/.config/vesktop/state.json" "${vencord}" || exit $?'
        rm "$out/share/applications/vesktop.desktop"
        cp ${pkgs.vesktop}/share/applications/vesktop.desktop "$out/share/applications/vesktop.desktop"
        substituteInPlace "$out/share/applications/vesktop.desktop" \
          --replace-fail 'Exec=vesktop' "Exec=$out/bin/vesktop"
      '';
    };
  in {
    home-manager.users.${username} = {
      config,
      lib,
      ...
    }: let
      # Reuse the pinned module's patching logic, including userPlugins, without
      # letting that mod derivation become an input to the Vesktop application.
      vencordRuntime = (import "${inputs.nixcord}/modules/lib/patching.nix" {inherit lib;}).applyPostPatch {
        cfg = config.programs.nixcord;
        pkg = config.programs.nixcord.discord.vencord.package;
      };
    in {
      imports = [ nixcordModule ];

      programs.nixcord = {
        enable = true;
        discord.enable = false;
        vesktop.enable = true;
        # Select Nix-managed Vencord through upstream's state setting, keeping
        # the stock Vesktop client identical to the public cached package.
        vesktop.useSystemVencord = false;
        vesktop.installPackage = false;

        config = {
          autoUpdate = false;
          autoUpdateNotification = false;
          plugins = {};
        };
      };

      home.packages = [
        (mkCachedVesktop vencordRuntime)
      ];

      xdg.configFile."vesktop/themes/.keep".text = "";
      xdg.configFile."vesktop/settings/.keep".text = "";

      # Optional: ensure settings.json exists declaratively
      xdg.configFile."vesktop/settings.json".source = vesktopSettingsFallback;

      home.activation.vesktopSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
        SETTINGS="$HOME/.config/vesktop/settings.json"

        # Only patch if file exists and is not a symlink
        if [ -f "$SETTINGS" ] && [ ! -L "$SETTINGS" ]; then
          ${patchMinimizeToTray} "$SETTINGS"
        fi
      '';
      home.activation.vesktopVencord = lib.hm.dag.entryAfter ["writeBoundary"] ''
        ${selectVencord} "$HOME/.config/vesktop/state.json" "${vencordRuntime}"
      '';
    };
  };
}
