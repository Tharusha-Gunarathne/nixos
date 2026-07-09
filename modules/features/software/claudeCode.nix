{inputs, ...}: {
  flake.nixosModules.claudeCode = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    home = config.home-manager.users.${username}.home.homeDirectory or "/home/${username}";
    claude = inputs.claude-plugins.inputs;

    # ~/.claude.json — merge only mcpServers.codegraph, never touch anything else
    # (Claude Code stores oauth state, project history, etc. in this same file).
    mergeClaudeJson = pkgs.writers.writePython3 "merge-claude-json" {} ''
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

      data.setdefault("mcpServers", {})
      data["mcpServers"]["codegraph"] = {
          "type": "stdio",
          "command": "codegraph",
          "args": ["serve", "--mcp"],
      }

      tmp = path + ".tmp"
      with open(tmp, "w", encoding="utf-8") as f:
          json.dump(data, f, indent=2)
          f.write("\n")
      os.replace(tmp, path)
    '';

    # ~/.claude/settings.json — append the auto-allow entry if missing,
    # preserving whatever else is already permitted.
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
    home-manager.users.${username} = {lib, ...}: {
      home.file = {
        "${home}/.claude/skills/caveman".source = "${claude.caveman-skill}/skills/caveman";
        "${home}/.claude/skills/caveman-commit".source = "${claude.caveman-skill}/skills/caveman-commit";
        "${home}/.claude/skills/caveman-compress".source = "${claude.caveman-skill}/skills/caveman-compress";
        "${home}/.claude/skills/caveman-help".source = "${claude.caveman-skill}/skills/caveman-help";
        "${home}/.claude/skills/caveman-review".source = "${claude.caveman-skill}/skills/caveman-review";
        "${home}/.claude/skills/caveman-stats".source = "${claude.caveman-skill}/skills/caveman-stats";
        "${home}/.claude/skills/cavecrew".source = "${claude.caveman-skill}/skills/cavecrew";

        "${home}/.claude/skills/taste-skill".source = "${claude.taste-skill}/skills/taste-skill";

        "${home}/.claude/skills/hallmark".source = "${claude.hallmark-skill}/skills/hallmark";
      };

      home.activation.codegraphMcpSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${home}/.claude"
        ${mergeClaudeJson} "${home}/.claude.json"
        ${mergeClaudeSettings} "${home}/.claude/settings.json"
      '';
    };
  };
}
