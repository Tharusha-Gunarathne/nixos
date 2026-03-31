{ self, inputs, ... }: {
  flake.homeManagerModules.noctalia = { config, pkgs, lib, osConfig, ... }:
  let
    username = osConfig.myConfig.username;
    watchDir = "/home/${username}/.config/noctalia";
    repoNoctaliaDir = "/home/${username}/nixos-configs/structure/modules/features/software/noctalia";

    syncScript = pkgs.writeShellScript "noctalia-sync" ''
      WATCH_DIR="${watchDir}"
      REPO_DIR="${repoNoctaliaDir}"
      CP="${pkgs.coreutils}/bin/cp"

      mkdir -p "$REPO_DIR"

      ${pkgs.inotify-tools}/bin/inotifywait -m -e close_write,moved_to "$WATCH_DIR" |
      while read -r dir event file; do
        if [[ "$file" == "settings.json" || "$file" == "plugins.json" ]]; then
          echo "Detected change: $file ($event)"
          $CP "$WATCH_DIR/$file" "$REPO_DIR/$file"
          echo "Copied $file to repo dir"
        fi
      done
    '';

    commitScript = pkgs.writeShellScript "noctalia-commit" ''
      REPO_ROOT="/home/${username}/nixos-configs/structure"
      GIT="${pkgs.git}/bin/git"

      cd "$REPO_ROOT"
      $GIT add "modules/features/software/noctalia/settings.json" \
               "modules/features/software/noctalia/plugins.json"

      if ! $GIT diff --cached --quiet; then
        $GIT commit -m "chore(noctalia): auto-sync config changes"
      fi
    '';
  in {
    imports = [ inputs.noctalia.noctalia-main.homeModules.default ];

    programs.noctalia-shell.enable = true;

    xdg.configFile = builtins.listToAttrs (map (name: {
      name = "noctalia/plugins/${name}";
      value = { source = inputs.noctalia.plugins.${name}; };
    }) (builtins.attrNames inputs.noctalia.plugins));

    home.activation.noctaliaSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p "${config.xdg.configHome}/noctalia"
      if [ ! -f "${config.xdg.configHome}/noctalia/settings.json" ]; then
        cp ${./settings.json} ${config.xdg.configHome}/noctalia/settings.json
      fi
    '';

    home.activation.noctaliaPlugins = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p "${config.xdg.configHome}/noctalia"
      if [ ! -f "${config.xdg.configHome}/noctalia/plugins.json" ]; then
        cp ${./plugins.json} ${config.xdg.configHome}/noctalia/plugins.json
      fi
    '';

    systemd.user.services.noctalia-sync = {
      Unit = {
        Description = "Watch and copy Noctalia config changes to repo";
        After = [ "default.target" ];
      };
      Service = {
        ExecStart = "${syncScript}";
        Restart = "always";
        RestartSec = "3s";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    systemd.user.services.noctalia-commit = {
      Unit.Description = "Commit pending Noctalia config changes to git";
      Service = {
        Type = "oneshot";
        ExecStart = "${commitScript}";
      };
    };

    systemd.user.timers.noctalia-commit = {
      Unit.Description = "Timer for Noctalia config auto-commit";
      Timer = {
        OnBootSec = "15min";
        OnUnitActiveSec = "15min";
        Unit = "noctalia-commit.service";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
