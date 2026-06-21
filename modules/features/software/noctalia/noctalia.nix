{
  inputs,
  self,
  localConfig,
  ...
}: {
  flake.nixosModules.noctalia = {
    config,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
    repoRoot = config.myConfig.repoRoot;
  in {
    imports = [
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
        stateDir = "${config.xdg.stateHome}/noctalia";
        repoDir = "${repoRoot}/modules/features/software/noctalia";
        fileName = "settings.toml";
        homeDir = config.home.homeDirectory;

        capitalize = s:
          if s == ""
          then s
          else lib.toUpper (builtins.substring 0 1 s) + builtins.substring 1 (builtins.stringLength s - 1) s;

        configuredDisplayName = localConfig.user.display_name or "";
        displayName =
          if configuredDisplayName != ""
          then configuredDisplayName
          else lib.concatStringsSep "-" (map capitalize (lib.splitString "-" username));

        # The git clean filter (modules/features/software/git.nix) replaces
        # real personal info with these tokens before settings.toml is
        # staged or committed. The real working-tree file is never touched
        # by git, so these tokens only ever show up in REPO_PATH right after
        # checking out this repo fresh on a (possibly different) machine.
        # This script restores the current machine's real values in that
        # case; in normal day-to-day sync it's a no-op pass-through, since
        # these exact strings never occur in real settings data.
        #
        # Token strings here MUST match PERSONAL_VALUES in git.nix.
        expandPlaceholdersScript = pkgs.writeShellScript "noctalia-expand-placeholders" ''
          set -euo pipefail
          SRC="$1"
          DST="$2"
          ${pkgs.gnused}/bin/sed \
            -e "s|REDACTED-HOME|${homeDir}|g" \
            -e "s|REDACTED-USERNAME|${username}|g" \
            -e "s|REDACTED-DISPLAY-NAME|${displayName}|g" \
            "$SRC" > "$DST"
        '';

        syncScript = pkgs.writeShellScript "noctalia-sync" ''
          set -euo pipefail
          STATE_DIR="${stateDir}"
          REPO_DIR="${repoDir}"
          FILE="${fileName}"
          EXPAND="${expandPlaceholdersScript}"
          CP="${pkgs.coreutils}/bin/cp"
          INOTIFY="${pkgs.inotify-tools}/bin/inotifywait"
          SHA="${pkgs.coreutils}/bin/sha256sum"
          CUT="${pkgs.coreutils}/bin/cut"
          STAT="${pkgs.coreutils}/bin/stat"
          MARKER_DIR="''${XDG_RUNTIME_DIR:-/tmp}/noctalia-sync"
          DEBOUNCE_SECONDS=2.0

          mkdir -p "$STATE_DIR" "$REPO_DIR" "$MARKER_DIR"

          STATE_PATH="$STATE_DIR/$FILE"
          REPO_PATH="$REPO_DIR/$FILE"
          STATE_SELF_WRITE="$MARKER_DIR/state-self-write.sha256"
          REPO_SELF_WRITE="$MARKER_DIR/repo-self-write.sha256"

          hash_of() {
            [ -f "$1" ] && "$SHA" "$1" | "$CUT" -d' ' -f1 || echo ""
          }

          write_atomic() {
            local content="$1" dest="$2"
            mkdir -p "$(dirname "$dest")"
            local tmp
            tmp="$(mktemp "$(dirname "$dest")/.tmp.XXXXXX")"
            printf '%s' "$content" > "$tmp"
            mv -f "$tmp" "$dest"
          }

          # $1=src $2=dst $3=incoming_marker $4=outgoing_marker $5=label
          # $6="1" to run placeholder expansion on the way through (repo→state only)
          sync_one() {
            local src="$1" dst="$2" incoming_marker="$3" outgoing_marker="$4" label="$5" expand="$6"

            local src_hash
            src_hash="$(hash_of "$src")"

            if [ -f "$incoming_marker" ] && [ "$(cat "$incoming_marker")" = "$src_hash" ]; then
              rm -f "$incoming_marker"
              return 0
            fi

            local scratch
            scratch="$(mktemp)"
            if [ "$expand" = "1" ]; then
              "$EXPAND" "$src" "$scratch"
            else
              "$CP" "$src" "$scratch"
            fi

            local new_hash dst_hash
            new_hash="$(hash_of "$scratch")"
            dst_hash="$(hash_of "$dst")"

            if [ "$new_hash" != "$dst_hash" ]; then
              write_atomic "$new_hash" "$outgoing_marker"
              mv -f "$scratch" "$dst"
              chmod 644 "$dst"
              echo "[noctalia-sync] $label"
            else
              rm -f "$scratch"
            fi
          }

          state_to_repo() {
            sync_one "$STATE_PATH" "$REPO_PATH" "$STATE_SELF_WRITE" "$REPO_SELF_WRITE" \
              "state→repo: $FILE" 0
          }

          repo_to_state() {
            sync_one "$REPO_PATH" "$STATE_PATH" "$REPO_SELF_WRITE" "$STATE_SELF_WRITE" \
              "repo→state: $FILE (placeholders expanded)" 1
          }

          reconcile_on_start() {
            if [ -f "$REPO_PATH" ] && [ ! -f "$STATE_PATH" ]; then
              echo "[noctalia-sync] startup reconcile: seeding state from repo"
              repo_to_state
              return
            fi
            if [ -f "$STATE_PATH" ] && [ ! -f "$REPO_PATH" ]; then
              echo "[noctalia-sync] startup reconcile: seeding repo from state"
              state_to_repo
              return
            fi
            if [ -f "$STATE_PATH" ] && [ -f "$REPO_PATH" ]; then
              local state_mtime repo_mtime
              state_mtime="$("$STAT" -c %Y "$STATE_PATH")"
              repo_mtime="$("$STAT" -c %Y "$REPO_PATH")"
              if [ "$state_mtime" -gt "$repo_mtime" ]; then
                echo "[noctalia-sync] startup reconcile: state is newer"
                state_to_repo
              elif [ "$repo_mtime" -gt "$state_mtime" ]; then
                echo "[noctalia-sync] startup reconcile: repo is newer"
                repo_to_state
              fi
            fi
          }

          watch_debounced() {
            local dir="$1" action="$2"
            local dirty=0 changed_file

            "$INOTIFY" -m -e close_write,moved_to --format '%f' "$dir" 2>/dev/null |
              while true; do
                if read -t "$DEBOUNCE_SECONDS" -r changed_file; then
                  [ "$changed_file" = "$FILE" ] && dirty=1
                elif [ "$dirty" = "1" ]; then
                  dirty=0
                  "$action"
                fi
              done
          }

          reconcile_on_start

          watch_debounced "$STATE_DIR" state_to_repo &
          watch_debounced "$REPO_DIR" repo_to_state &

          wait
        '';
      in {
        imports = [inputs.noctalia.noctalia-main.homeModules.default];

        programs.noctalia.enable = true;

        home.activation.noctaliaSeedSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
          mkdir -p "${stateDir}"
          STATE="${stateDir}/${fileName}"
          REPO="${repoDir}/${fileName}"

          if [ -f "$REPO" ] && [ ! -e "$STATE" ]; then
            ${expandPlaceholdersScript} "$REPO" "$STATE"
            echo "[noctalia] Seeded settings.toml from repo (fresh state dir, placeholders expanded)"
          fi
        '';

        systemd.user.services.noctalia-sync = {
          Unit = {
            Description = "Bidirectional sync: Noctalia settings.toml ↔ repo (debounced, self-write aware, reconciles on start)";
            After = ["default.target"];
          };
          Service = {
            ExecStart = "${syncScript}";
            Restart = "always";
            RestartSec = "3s";
            TimeoutStopSec = "5s";
            KillMode = "control-group";
          };
          Install.WantedBy = ["default.target"];
        };
      };
    };
  };
}
