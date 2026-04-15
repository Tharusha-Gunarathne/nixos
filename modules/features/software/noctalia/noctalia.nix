{
  inputs,
  self,
  ...
}: {
  flake.nixosModules.noctalia = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
    repoRoot = config.myConfig.repoRoot;
  in {
    imports = [
      self.nixosModules.noctaliaPluginSettings
      self.nixosModules.noctaliaKitty
      self.nixosModules.noctaliaNiri
      self.nixosModules.noctaliaVscode
      self.nixosModules.noctaliaSpotify
      self.nixosModules.noctaliaDiscord
    ];

    config = lib.mkIf config.myConfig.shell.noctalia {
      home-manager.users.${username} = {
        config,
        pkgs,
        lib,
        ...
      }: let
        configDir = "${config.xdg.configHome}/noctalia";
        repoDir = "${repoRoot}/modules/features/software/noctalia";

        syncScript = pkgs.writeShellScript "noctalia-sync" ''
          set -euo pipefail
          CONFIG_DIR="${configDir}"
          REPO_DIR="${repoDir}"
          CP="${pkgs.coreutils}/bin/cp"
          INOTIFY="${pkgs.inotify-tools}/bin/inotifywait"
          LOCK_DIR="/tmp/noctalia-sync-lock"

          mkdir -p "$CONFIG_DIR" "$REPO_DIR" "$LOCK_DIR"

          acquire_lock() {
            local file="$1"
            local lockfile="$LOCK_DIR/$file.lock"
            if [ -f "$lockfile" ]; then
              return 1
            fi
            touch "$lockfile"
            ( sleep 4; rm -f "$lockfile" ) &
            return 0
          }

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

          wait
        '';

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

        home.activation.noctaliaCleanupBackups = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
          rm -f \
            "${configDir}/settings.json.backup" \
            "${configDir}/plugins.json.backup" \
            "${configDir}/settings.json.hmbackup" \
            "${configDir}/plugins.json.hmbackup"

          # Remove stale plugin backup directories that can register duplicate manifests
          # (e.g. wallcards.backup) and override expected plugin behavior.
          if [ -d "${configDir}/plugins" ]; then
            find "${configDir}/plugins" -maxdepth 1 -type d -name '*.backup' -exec rm -rf {} +
          fi

          # Clear stale QML/pipeline caches so plugin QML changes are picked up reliably.
          rm -rf "$HOME/.cache/noctalia-qs/qmlcache" \
                 "$HOME/.cache/noctalia-qs/qtpipelinecache-x86_64-little_endian-lp64"
        '';

        home.activation.noctaliaSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
          mkdir -p "${configDir}"
          SETTINGS="${configDir}/settings.json"
          REPO_SETTINGS="${repoDir}/settings.json"

          if [ -f "$REPO_SETTINGS" ]; then
            if [ -L "$SETTINGS" ] || [ ! -e "$SETTINGS" ] || \
               ! ${pkgs.diffutils}/bin/diff -q "$REPO_SETTINGS" "$SETTINGS" > /dev/null 2>&1; then
              rm -f "$SETTINGS"
              ${pkgs.coreutils}/bin/install -m 644 "$REPO_SETTINGS" "$SETTINGS"
              echo "[noctalia] Seeded settings.json from repo"
            fi
          elif [ -L "$SETTINGS" ] || [ ! -e "$SETTINGS" ]; then
            rm -f "$SETTINGS"
            ${pkgs.coreutils}/bin/install -m 644 ${./settings.json} "$SETTINGS"
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
          # Temporarily disabled: keep the timer definition, but do not auto-enable it.
          # Install.WantedBy = ["timers.target"];
        };
      };
    };
  };
}
