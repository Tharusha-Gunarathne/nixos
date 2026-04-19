{...}: {
  flake.nixosModules.niri = {
    config,
    lib,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    shell = config.myConfig.shell;
    configPath = "${config.myConfig.repoRoot}/modules/features/software/niri/config.kdl";
    spawnLikeFocusedWindow = pkgs.writeShellScriptBin "niri-spawn-like-focused-window" ''
      set -euo pipefail

      NIRI="${pkgs.niri}/bin/niri"
      JQ="${pkgs.jq}/bin/jq"
      GTK_LAUNCH="${pkgs.gtk3}/bin/gtk-launch"
      BASENAME="${pkgs.coreutils}/bin/basename"
      GREP="${pkgs.gnugrep}/bin/grep"
      NOHUP="${pkgs.coreutils}/bin/nohup"
      SED="${pkgs.gnused}/bin/sed"
      TR="${pkgs.coreutils}/bin/tr"
      DATA_DIRS="''${XDG_DATA_DIRS:-/run/current-system/sw/share:/usr/local/share:/usr/share}"

      try_desktop_id() {
        desktop_id="$1"
        [ -n "$desktop_id" ] || return 1
        case "$desktop_id" in
          *.desktop) desktop_id="''${desktop_id%.desktop}" ;;
        esac
        "$GTK_LAUNCH" "$desktop_id" >/dev/null 2>&1
      }

      find_desktop_file_by_id() {
        desktop_id="$1"
        [ -n "$desktop_id" ] || return 1
        case "$desktop_id" in
          *.desktop) desktop_id="''${desktop_id%.desktop}" ;;
        esac

        old_ifs="$IFS"
        IFS=":"
        for data_dir in "$HOME/.local/share" $DATA_DIRS; do
          apps_dir="$data_dir/applications"
          [ -d "$apps_dir" ] || continue

          desktop_file="$apps_dir/$desktop_id.desktop"
          if [ -f "$desktop_file" ]; then
            printf '%s\n' "$desktop_file"
            IFS="$old_ifs"
            return 0
          fi
        done
        IFS="$old_ifs"
        return 1
      }

      find_desktop_id_from_wmclass() {
        wmclass="$1"
        [ -n "$wmclass" ] || return 1

        old_ifs="$IFS"
        IFS=":"
        for data_dir in "$HOME/.local/share" $DATA_DIRS; do
          apps_dir="$data_dir/applications"
          [ -d "$apps_dir" ] || continue

          for desktop_file in "$apps_dir"/*.desktop; do
            [ -e "$desktop_file" ] || continue
            if "$GREP" -Fqi "StartupWMClass=$wmclass" "$desktop_file" || \
              "$GREP" -Fqi "X-GNOME-WMClass=$wmclass" "$desktop_file"; then
              "$BASENAME" "$desktop_file" .desktop
              IFS="$old_ifs"
              return 0
            fi
          done
        done
        IFS="$old_ifs"
        return 1
      }

      launch_exec_from_desktop_file() {
        desktop_file="$1"
        [ -f "$desktop_file" ] || return 1

        exec_line="$($SED -n 's/^Exec=//p' "$desktop_file" | $SED -n '1p')"
        [ -n "$exec_line" ] || return 1

        # Drop desktop entry field codes (%U, %f, %i, etc.) before launching.
        sanitized_exec="$(printf '%s\n' "$exec_line" | $SED -E 's/%%/__PERCENT__/g; s/[[:space:]]+%[[:alpha:]]//g; s/%[[:alpha:]]//g; s/__PERCENT__/%/g; s/[[:space:]]+$//; s/^[[:space:]]+//')"
        [ -n "$sanitized_exec" ] || return 1

        "$NOHUP" sh -lc "$sanitized_exec" >/dev/null 2>&1 &
        return 0
      }

      focused_json="$($NIRI msg -j focused-window 2>/dev/null || true)"
      if [ -z "$focused_json" ] || [ "$focused_json" = "null" ]; then
        exit 0
      fi

      app_id="$(printf '%s\n' "$focused_json" | $JQ -r '.app_id // empty' 2>/dev/null || true)"
      pid="$(printf '%s\n' "$focused_json" | $JQ -r '.pid // empty' 2>/dev/null || true)"

      if [ -n "$app_id" ]; then
        desktop_file="$(find_desktop_file_by_id "$app_id" || true)"
        if [ -z "$desktop_file" ]; then
          wmclass_desktop_id="$(find_desktop_id_from_wmclass "$app_id" || true)"
          if [ -n "$wmclass_desktop_id" ]; then
            desktop_file="$(find_desktop_file_by_id "$wmclass_desktop_id" || true)"
          fi
        fi

        if [ -n "$desktop_file" ] && launch_exec_from_desktop_file "$desktop_file"; then
          exit 0
        fi

        if try_desktop_id "$app_id"; then
          exit 0
        fi

        wmclass_desktop_id="$(find_desktop_id_from_wmclass "$app_id" || true)"
        if [ -n "$wmclass_desktop_id" ] && try_desktop_id "$wmclass_desktop_id"; then
          exit 0
        fi
      fi

      if [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ]; then
        cmd_path="$(cat "/proc/$pid/cmdline" 2>/dev/null | "$TR" '\000' '\n' | "$SED" -n '1p')"
        if [ -n "$cmd_path" ]; then
          cmd_name="$("$BASENAME" "$cmd_path")"
          if try_desktop_id "$cmd_name"; then
            exit 0
          fi
          if [ -x "$cmd_path" ]; then
            exec "$cmd_path"
          fi
        fi
      fi

      if [ -n "$pid" ] && [ -r "/proc/$pid/comm" ]; then
        proc_cmd="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
        if [ -n "$proc_cmd" ]; then
          if try_desktop_id "$proc_cmd"; then
            exit 0
          fi
          exec "$proc_cmd"
        fi
      fi

      exit 0
    '';
  in {
    programs.niri.enable = true;

    home-manager.users.${username} = {
      config,
      lib,
      pkgs,
      ...
    }: {
      home.packages = [
        spawnLikeFocusedWindow
      ];

      xdg.configFile."niri/config.kdl" = {
        source = config.lib.file.mkOutOfStoreSymlink "${configPath}";
      };

      home.activation.niriCleanupShellIncludes = lib.hm.dag.entryAfter ["writeBoundary"] ''
        NIRI_CONFIG="${configPath}"
        if [ -f "$NIRI_CONFIG" ] && [ "${
          if shell.noctalia
          then "true"
          else "false"
        }" != "true" ]; then
          ${pkgs.gnused}/bin/sed -i '/include "\.\/noctalia\.kdl"/d' "$NIRI_CONFIG"
        fi
      '';
    };
  };
}
