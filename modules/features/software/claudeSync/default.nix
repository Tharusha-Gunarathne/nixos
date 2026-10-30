{...}: {
  # Shares Claude Code sessions, auto-memory, skills, agents and plugin
  # settings with the Windows install on the dual-boot NTFS drives.
  # Windows side: run <sharedDir>\_sync\bootstrap.ps1 once (copied there below).
  flake.nixosModules.claudeSync = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myConfig.claudeSync;
    username = config.myConfig.primaryUser;
    home = config.home-manager.users.${username}.home.homeDirectory or "/home/${username}";

    # D_Drive -> D, E_Drive -> E
    driveMaps =
      map (d: "/mnt/${d.name}=${builtins.substring 0 1 d.name}")
      (builtins.filter (d: builtins.match "[A-Z]_Drive" d.name != null)
        config.myConfig.storage.dataDrives);

    manifest = ./shared.json;

    # Linux-side tool. claude-shared wraps it with this machine's paths.
    claude-shared-unwrapped = pkgs.writers.writePython3Bin "claude-shared-unwrapped" {
      flakeIgnore = ["E501" "W503" "W504"];
    } (builtins.readFile ./claude-shared.py);

    # Refreshes shared skills from their upstream repos (bun, same script on
    # Windows). Background, at most daily per repo; see skill-update.ts.
    skill-update = pkgs.writeShellScriptBin "claude-skill-update" ''
      export PATH=${lib.makeBinPath [pkgs.gnutar pkgs.gzip]}:$PATH
      exec ${pkgs.bun}/bin/bun ${./skill-update.ts} --shared ${lib.escapeShellArg cfg.sharedDir} \
        --manifest ${manifest} --lock "$HOME/.agents/.skill-lock.json" "$@"
    '';

    sharedArgs = lib.escapeShellArgs (
      [
        "--shared"
        cfg.sharedDir
        "--manifest"
        "${manifest}"
        # Stable profile path, so the registered hook survives rebuilds.
        "--hook-command"
        "/etc/profiles/per-user/${username}/bin/claude-shared hook"
        "--skill-updater"
        "${skill-update}/bin/claude-skill-update"
      ]
      ++ lib.concatMap (m: ["--map" m]) driveMaps
    );

    claude-shared = pkgs.writeShellScriptBin "claude-shared" ''
      exec ${claude-shared-unwrapped}/bin/claude-shared-unwrapped ${sharedArgs} "$@"
    '';

    # Links the current directory's project into the shared store, then
    # hands off to the real binary. hiPrio wins over claude-code's bin/claude.
    claudeWrapper = lib.hiPrio (pkgs.writeShellScriptBin "claude" ''
      ${claude-shared}/bin/claude-shared prepare "$PWD" || true
      exec ${pkgs.claude-code}/bin/claude "$@"
    '');

    # Claude with its own config dir: nothing done there is shared or
    # recorded (see claude-sandbox.sh). Windows: _sync/claude-sandbox.ps1.
    claude-sandbox = pkgs.writeShellScriptBin "claude-sandbox" ''
      export PATH=${lib.makeBinPath [pkgs.jq pkgs.coreutils pkgs.findutils pkgs.gnused]}:$PATH
      export CLAUDE_SANDBOX_CLAUDE="''${CLAUDE_SANDBOX_CLAUDE:-${pkgs.claude-code}/bin/claude}"
      ${builtins.readFile ./claude-sandbox.sh}
    '';

    # headroom-ai isn't in nixpkgs. Pinned to the version Windows runs
    # (uv tool install "headroom-ai[all]"); uv caches it after the first run.
    headroomSpec = "headroom-ai[all]==0.39.1";
    headroom = pkgs.symlinkJoin {
      name = "headroom";
      paths = map (bin:
        pkgs.writeShellScriptBin bin ''
          exec ${pkgs.uv}/bin/uvx --python 3.13 --from ${lib.escapeShellArg headroomSpec} ${bin} "$@"
        '') ["headroom" "headroom-cache-ttl"];
    };

    backupDir = "${home}/.local/state/claude-shared/backups";

    # ~/.claude/settings.json — append the codegraph auto-allow entry if
    # missing, preserving whatever else is already permitted. (The codegraph
    # MCP server itself comes from shared.json.)
    mergeClaudeSettings = pkgs.writers.writePython3 "merge-claude-settings" {} ''
      import json
      import os
      import sys

      path = sys.argv[1]

      try:
          with open(path, "r", encoding="utf-8") as f:
              data = json.load(f)
      except Exception:
          data = {}

      if not isinstance(data, dict):
          data = {}

      perms = data.setdefault("permissions", {})
      allow = perms.setdefault("allow", [])
      if "mcp__codegraph__*" not in allow:
          allow.append("mcp__codegraph__*")

      tmp = path + ".tmp"
      with open(tmp, "w", encoding="utf-8") as f:
          json.dump(data, f, indent=2)
          f.write("\n")
      os.replace(tmp, path)
    '';
  in {
    options.myConfig.claudeSync = {
      enable = lib.mkEnableOption "sharing Claude Code state with Windows" // {default = true;};
      sharedDir = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/E_Drive/.claude-shared";
        description = "Shared store on an NTFS drive Windows also sees (E:\\.claude-shared).";
      };
      backupDays = lib.mkOption {
        type = lib.types.int;
        default = 7;
        description = "Daily snapshots of the shared store to keep on ext4.";
      };
    };

    config = lib.mkIf cfg.enable {
      home-manager.users.${username} = {lib, ...}: {
        home.packages = [claudeWrapper claude-shared claude-sandbox skill-update headroom];

        # ~/.claude-mem/settings.json is shared with Windows, which writes its
        # own absolute C:\ paths into it. Linux reads those as relative names
        # and creates "C:\Users\..." folders in whatever directory claude runs
        # in. claude-mem lets the environment override the file.
        home.sessionVariables = {
          CLAUDE_MEM_DATA_DIR = "$HOME/.claude-mem";
          CLAUDE_MEM_TRANSCRIPTS_CONFIG_PATH = "$HOME/.claude-mem/transcript-watch.json";
        };

        # Skills aren't pinned in Nix: they live in the shared store, so a
        # skill added on either OS shows up everywhere and updates in place.
        home.activation.codegraphMcpSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
          mkdir -p "${home}/.claude"
          ${mergeClaudeSettings} "${home}/.claude/settings.json"
        '';

        home.activation.claudeSharedSync = lib.hm.dag.entryAfter ["writeBoundary" "codegraphMcpSetup"] ''
          ${claude-shared}/bin/claude-shared sync || true
          # Ship the Windows half of the setup through the shared drive.
          if [ -d ${lib.escapeShellArg cfg.sharedDir} ]; then
            mkdir -p ${lib.escapeShellArg "${cfg.sharedDir}/_sync"}
            cp -f ${./bootstrap.ps1} ${lib.escapeShellArg "${cfg.sharedDir}/_sync/bootstrap.ps1"}
            cp -f ${./hook.ps1} ${lib.escapeShellArg "${cfg.sharedDir}/_sync/hook.ps1"}
            cp -f ${./skill-update.ts} ${lib.escapeShellArg "${cfg.sharedDir}/_sync/skill-update.ts"}
            cp -f ${./claude-sandbox.ps1} ${lib.escapeShellArg "${cfg.sharedDir}/_sync/claude-sandbox.ps1"}
            cp -f ${manifest} ${lib.escapeShellArg "${cfg.sharedDir}/_sync/shared.json"}
            cp -f ${./WORKSPACE-README.md} ${lib.escapeShellArg "${cfg.sharedDir}/README.md"}
            # Old one-shot snapshots: re-reading them would undo uninstalls.
            rm -f ${lib.escapeShellArg "${cfg.sharedDir}/_sync/installed-linux.json"} \
              ${lib.escapeShellArg "${cfg.sharedDir}/_sync/installed-windows.json"}
          fi
        '';

        # settings.json only declares plugins; this installs any that are
        # missing. Runs at login and again whenever shared.json changes.
        systemd.user.services.claude-shared-plugins = {
          Unit = {
            Description = "Install shared Claude Code plugins";
            After = ["network-online.target"];
            X-Restart-Triggers = ["${manifest}"];
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            Environment = "PATH=/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin";
            ExecStart = "${claude-shared}/bin/claude-shared plugins --claude ${pkgs.claude-code}/bin/claude";
          };
          Install.WantedBy = ["default.target"];
        };

        # Daily hardlinked snapshots: covers a bad delete through a Windows junction.
        systemd.user.services.claude-shared-backup = {
          Unit.Description = "Snapshot the shared Claude Code store";
          Service = {
            Type = "oneshot";
            ExecStart = toString (pkgs.writeShellScript "claude-shared-backup" ''
              set -eu
              src=${lib.escapeShellArg cfg.sharedDir}
              [ -d "$src/projects" ] || { echo "shared store unavailable, skipping"; exit 0; }
              ${claude-shared}/bin/claude-shared sync || true
              dest=${lib.escapeShellArg backupDir}
              mkdir -p "$dest"
              today="$dest/$(date +%F)"
              latest=$(ls -1d "$dest"/????-??-?? 2>/dev/null | grep -v "$today" | tail -n1 || true)
              # _sync/ is regenerated, except the append-only install registry.
              ${pkgs.rsync}/bin/rsync -a --delete \
                --include '_sync/' --include '_sync/registry.jsonl' --exclude '_sync/*' \
                ''${latest:+--link-dest="$latest"} "$src/" "$today/"
              ls -1d "$dest"/????-??-?? | head -n -${toString cfg.backupDays} | xargs -r rm -rf
            '');
          };
        };
        systemd.user.timers.claude-shared-backup = {
          Unit.Description = "Daily snapshot of the shared Claude Code store";
          Timer = {
            OnCalendar = "daily";
            Persistent = true;
          };
          Install.WantedBy = ["timers.target"];
        };
      };
    };
  };
}
