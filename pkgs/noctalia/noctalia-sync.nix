{ config, pkgs, username, baseDir, ... }:

let
  repoDir = "${baseDir}/pkgs/noctalia";
  watchDir = "${config.xdg.configHome}/noctalia";

  syncScript = pkgs.writeShellScript "noctalia-sync" ''
    WATCH_DIR="${watchDir}"
    REPO_DIR="${repoDir}"
    REPO_ROOT="${baseDir}"

    mkdir -p "$REPO_DIR"

    inotifywait -m -e close_write,moved_to "$WATCH_DIR" |
    while read -r dir event file; do
      if [[ "$file" == "settings.json" || "$file" == "plugins.json" ]]; then
        echo "Detected change: $file ($event)"
        cp "$WATCH_DIR/$file" "$REPO_DIR/$file"

        cd "$REPO_ROOT"
        git add "pkgs/noctalia/$file"

        if ! git diff --cached --quiet; then
          git commit -m "chore(noctalia): auto-sync $file"
          echo "Committed $file"
        else
          echo "No change in $file, skipping commit"
        fi
      fi
    done
  '';
in
{
  systemd.user.services.noctalia-sync = {
    Unit = {
      Description = "Auto-sync Noctalia config changes to nixos-configs repo";
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
}