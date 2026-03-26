{ config, pkgs, username, baseDir, ... }:

let
  repoDir = "/home/${username}/nixos-configs/structure/pkgs/noctalia";
  watchDir = "/home/${username}/.config/noctalia";

  # Service 1: watches and copies files immediately on change
  syncScript = pkgs.writeShellScript "noctalia-sync" ''
    WATCH_DIR="${watchDir}"
    REPO_DIR="${repoDir}"

    mkdir -p "$REPO_DIR"

    ${pkgs.inotify-tools}/bin/inotifywait -m -e close_write,moved_to "$WATCH_DIR" |
    while read -r dir event file; do
      if [[ "$file" == "settings.json" || "$file" == "plugins.json" ]]; then
        echo "Detected change: $file ($event)"
        cp "$WATCH_DIR/$file" "$REPO_DIR/$file"
        echo "Copied $file to repo dir"
      fi
    done
  '';

  # Service 2: commits anything staged every 15 minutes
  commitScript = pkgs.writeShellScript "noctalia-commit" ''
    REPO_ROOT="${baseDir}"

    cd "$REPO_ROOT"
    git add "pkgs/noctalia/settings.json" "pkgs/noctalia/plugins.json"

    if ! git diff --cached --quiet; then
      git commit -m "chore(noctalia): auto-sync config changes"
      echo "Committed noctalia changes"
    else
      echo "No changes to commit"
    fi
  '';
in
{
  # Watcher service — runs continuously
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

  # Commit service — triggered by the timer
  systemd.user.services.noctalia-commit = {
    Unit = {
      Description = "Commit pending Noctalia config changes to git";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${commitScript}";
    };
  };

  # Timer — runs the commit service every 15 minutes
  systemd.user.timers.noctalia-commit = {
    Unit = {
      Description = "Timer for Noctalia config auto-commit";
    };
    Timer = {
      OnBootSec = "15min";
      OnUnitActiveSec = "15min";
      Unit = "noctalia-commit.service";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
