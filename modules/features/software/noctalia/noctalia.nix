{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.noctalia = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.username;
    repoRoot = config.myConfig.repoRoot;
  in {
    home-manager.users.${username} = {
      config,
      pkgs,
      lib,
      ...
    }: let
      watchDir = "${config.xdg.configHome}/noctalia";
      repoNoctaliaDir = "${repoRoot}/modules/features/software/noctalia";

      # Noctalia sync script - watches for changes in the Noctalia config directory and copies them to the repo
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

      # Noctalia commit script - commits only settings.json/plugins.json via a temporary index
      commitScript = pkgs.writeShellScript "noctalia-commit" ''
        REPO_ROOT="${repoRoot}"
        GIT="${pkgs.git}/bin/git"

        cd "$REPO_ROOT"

        TMP_INDEX=$(mktemp)
        cleanup() { rm -f "$TMP_INDEX"; }
        trap cleanup EXIT

        GIT_INDEX_FILE="$TMP_INDEX" "$GIT" read-tree HEAD

        for path in modules/features/software/noctalia/settings.json \
                   modules/features/software/noctalia/plugins.json; do
          if [ -e "$path" ]; then
            GIT_INDEX_FILE="$TMP_INDEX" "$GIT" add "$path"
          fi
        done

        if GIT_INDEX_FILE="$TMP_INDEX" "$GIT" diff --cached --quiet; then
          exit 0
        fi

        GIT_INDEX_FILE="$TMP_INDEX" "$GIT" commit -m "chore(noctalia): auto-sync config changes"
      '';
    in {
      imports = [inputs.noctalia.noctalia-main.homeModules.default];

      programs.noctalia-shell.enable = true;

      xdg.configFile = builtins.listToAttrs (map (name: {
        name = "noctalia/plugins/${name}";
        value = {source = inputs.noctalia.plugins.${name};};
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
          After = ["default.target"];
        };
        Service = {
          ExecStart = "${syncScript}";
          Restart = "always";
          RestartSec = "3s";
        };
        Install = {
          WantedBy = ["default.target"];
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
        Install.WantedBy = ["timers.target"];
      };
    };
  };
}
