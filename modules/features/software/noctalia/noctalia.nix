{inputs, ...}: {
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
      configDir = "${config.xdg.configHome}/noctalia";
      repoDir = "${repoRoot}/modules/features/software/noctalia";

      # Bidirectional sync script.
      #
      # Watches BOTH the config dir and the repo dir simultaneously using two
      # inotifywait processes. When a change is detected in either direction,
      # it copies to the other side — with a 1-second cooldown flag to prevent
      # the copy itself from triggering a loop back.
      syncScript = pkgs.writeShellScript "noctalia-sync" ''
        set -euo pipefail
        CONFIG_DIR="${configDir}"
        REPO_DIR="${repoDir}"
        CP="${pkgs.coreutils}/bin/cp"
        INOTIFY="${pkgs.inotify-tools}/bin/inotifywait"
        LOCK_DIR="/tmp/noctalia-sync-lock"

        mkdir -p "$CONFIG_DIR" "$REPO_DIR" "$LOCK_DIR"

        # Acquire a per-file cooldown lock to prevent ping-pong loops.
        # Returns 0 (success) if no lock exists and sets one; 1 if locked.
        acquire_lock() {
          local file="$1"
          local lockfile="$LOCK_DIR/$file.lock"
          if [ -f "$lockfile" ]; then
            return 1
          fi
          touch "$lockfile"
          # Auto-release after 2 seconds
          ( sleep 4; rm -f "$lockfile" ) &
          return 0
        }

        # Watch config dir → copy to repo
        (
          "$INOTIFY" -m -e close_write,moved_to "$CONFIG_DIR" 2>/dev/null |
          while read -r _dir _event file; do
            if [[ "$file" == "settings.json" || "$file" == "plugins.json" ]]; then
              if acquire_lock "config-to-repo-$file"; then
                echo "[noctalia-sync] config→repo: $file"
                "$CP" "$CONFIG_DIR/$file" "$REPO_DIR/$file"
              fi
            fi
          done
        ) &

        # Watch repo dir → copy to config
        (
          "$INOTIFY" -m -e close_write,moved_to "$REPO_DIR" 2>/dev/null |
          while read -r _dir _event file; do
            if [[ "$file" == "settings.json" || "$file" == "plugins.json" ]]; then
              if acquire_lock "repo-to-config-$file"; then
                echo "[noctalia-sync] repo→config: $file"
                "$CP" "$REPO_DIR/$file" "$CONFIG_DIR/$file"
              fi
            fi
          done
        ) &

        # Wait for both watchers — if either dies the service restarts
        wait
      '';

      # Commit script — uses a temporary git index to avoid touching the
      # working tree index, committing only settings.json and plugins.json.
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

      # On every nixos-rebuild switch:
      #   1. If repo has settings.json → copy it to config (repo is source of truth)
      #   2. Else if config is a store symlink or missing → seed from the Nix store copy
      #   3. Else leave the existing writable config file alone
      home.activation.noctaliaSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${configDir}"
        SETTINGS="${configDir}/settings.json"
        REPO_SETTINGS="${repoDir}/settings.json"

        if [ -f "$REPO_SETTINGS" ]; then
          # Repo exists — always use it as source of truth on rebuild
          if [ -L "$SETTINGS" ] || [ ! -e "$SETTINGS" ] || \
             ! ${pkgs.diffutils}/bin/diff -q "$REPO_SETTINGS" "$SETTINGS" > /dev/null 2>&1; then
            rm -f "$SETTINGS"
            ${pkgs.coreutils}/bin/install -m 644 "$REPO_SETTINGS" "$SETTINGS"
            echo "[noctalia] Seeded settings.json from repo"
          fi
        elif [ -L "$SETTINGS" ] || [ ! -e "$SETTINGS" ]; then
          # No repo file yet — seed from Nix store (first ever setup)
          rm -f "$SETTINGS"
          ${pkgs.coreutils}/bin/install -m 644 ${./settings.json} "$SETTINGS"
          # Also copy into repo so future rebuilds use the repo as source of truth
          mkdir -p "${repoDir}"
          ${pkgs.coreutils}/bin/install -m 644 "$SETTINGS" "${repoDir}/settings.json"
          echo "[noctalia] Seeded settings.json from store (fresh system)"
        fi
      '';

      home.activation.noctaliaPlugins = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${configDir}"
        PLUGINS="${configDir}/plugins.json"
        REPO_PLUGINS="${repoDir}/plugins.json"

        if [ -f "$REPO_PLUGINS" ]; then
          if [ -L "$PLUGINS" ] || [ ! -e "$PLUGINS" ] || \
             ! ${pkgs.diffutils}/bin/diff -q "$REPO_PLUGINS" "$PLUGINS" > /dev/null 2>&1; then
            rm -f "$PLUGINS"
            ${pkgs.coreutils}/bin/install -m 644 "$REPO_PLUGINS" "$PLUGINS"
            echo "[noctalia] Seeded plugins.json from repo"
          fi
        elif [ -L "$PLUGINS" ] || [ ! -e "$PLUGINS" ]; then
          rm -f "$PLUGINS"
          ${pkgs.coreutils}/bin/install -m 644 ${./plugins.json} "$PLUGINS"
          mkdir -p "${repoDir}"
          ${pkgs.coreutils}/bin/install -m 644 "$PLUGINS" "${repoDir}/plugins.json"
          echo "[noctalia] Seeded plugins.json from store (fresh system)"
        fi
      '';

      # Bidirectional sync daemon — watches both dirs, copies on change
      systemd.user.services.noctalia-sync = {
        Unit = {
          Description = "Bidirectional sync: Noctalia config ↔ repo";
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

      # Periodic git commit of settings.json and plugins.json
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
