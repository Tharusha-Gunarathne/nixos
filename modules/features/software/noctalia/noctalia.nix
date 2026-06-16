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

        # ${VAR}-style placeholders, .env-style. Nix strings containing
        # the literal text "${...}" — plain text at this point, not
        # shell or Nix variables.
        homeToken = "\${NOCTALIA_HOME}";
        usernameToken = "\${NOCTALIA_USERNAME}";
        displayNameToken = "\${NOCTALIA_DISPLAY_NAME}";
        envsubstVars = "${homeToken} ${usernameToken} ${displayNameToken}";

        # Real values <-> ${VAR} placeholders.
        templateScript = pkgs.writeShellScript "noctalia-template" ''
          set -euo pipefail
          MODE="$1"
          SRC="$2"
          DST="$3"

          export NOCTALIA_HOME="${homeDir}"
          export NOCTALIA_USERNAME="${username}"
          export NOCTALIA_DISPLAY_NAME="${displayName}"

          TMP="$(mktemp)"
          trap 'rm -f "$TMP"' EXIT

          case "$MODE" in
            to-repo)
              # Single-quote the replacement text so bash doesn't expand
              # ''${NOCTALIA_HOME}-style tokens via the live env vars of the
              # same name — only the search side ($NOCTALIA_HOME etc.,
              # double-quoted) should be expanded here.
              ${pkgs.gnused}/bin/sed \
                -e "s|$NOCTALIA_HOME|"'${homeToken}'"|g" \
                -e "s|$NOCTALIA_USERNAME|"'${usernameToken}'"|g" \
                -e "s|$NOCTALIA_DISPLAY_NAME|"'${displayNameToken}'"|g" \
                "$SRC" > "$TMP"
              ;;
            to-state)
              ${pkgs.gettext}/bin/envsubst '${envsubstVars}' \
                < "$SRC" > "$TMP"
              ;;
            *)
              echo "[noctalia-template] unknown mode: $MODE" >&2
              exit 1
              ;;
          esac

          ${pkgs.coreutils}/bin/install -m 644 "$TMP" "$DST"
        '';

        syncScript = pkgs.writeShellScript "noctalia-sync" ''
          set -euo pipefail
          STATE_DIR="${stateDir}"
          REPO_DIR="${repoDir}"
          FILE="${fileName}"
          TEMPLATE="${templateScript}"
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

          sync_one() {
            local mode="$1" src="$2" dst="$3" incoming_marker="$4" outgoing_marker="$5" label="$6"

            local src_hash
            src_hash="$(hash_of "$src")"

            if [ -f "$incoming_marker" ] && [ "$(cat "$incoming_marker")" = "$src_hash" ]; then
              rm -f "$incoming_marker"
              return 0
            fi

            local scratch
            scratch="$(mktemp)"
            "$TEMPLATE" "$mode" "$src" "$scratch"

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
            sync_one to-repo "$STATE_PATH" "$REPO_PATH" "$STATE_SELF_WRITE" "$REPO_SELF_WRITE" \
              "state→repo: $FILE (templated)"
          }

          repo_to_state() {
            sync_one to-state "$REPO_PATH" "$STATE_PATH" "$REPO_SELF_WRITE" "$STATE_SELF_WRITE" \
              "repo→state: $FILE (expanded)"
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
            ${templateScript} to-state "$REPO" "$STATE"
            echo "[noctalia] Seeded settings.toml from repo (fresh state dir, expanded)"
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