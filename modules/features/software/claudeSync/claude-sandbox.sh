# claude-sandbox [--reset] [claude args...]
#
# Claude Code with its own config dir (~/.claude-sandbox), seeded from
# ~/.claude. Plugins, skills, MCP servers, sessions and claude-mem memories
# installed, removed or created there stay there: nothing reaches ~/.claude,
# the shared drive, Windows or the other Windows user. The sandbox keeps its
# own login (run /login once). --reset re-seeds it from ~/.claude.
set -eu
box="${CLAUDE_SANDBOX_DIR:-$HOME/.claude-sandbox}"
real="${CLAUDE_SANDBOX_FROM:-$HOME/.claude}"

if [ "${1:-}" = "--reset" ]; then
  shift
  if [ -d "$box" ]; then
    # Keep only the sandbox's login.
    find "$box" -mindepth 1 -maxdepth 1 ! -name .credentials.json -exec rm -rf {} +
  fi
fi

if [ ! -e "$box/.seeded" ]; then
  echo "claude-sandbox: copying $real into $box (once; --reset to redo)" >&2
  mkdir -p "$box/skills"
  # Real copies, not links: deleting something here must never reach the
  # originals (plugins hold absolute paths, rewritten below).
  [ -d "$real/plugins" ] && cp -a "$real/plugins" "$box/"
  for f in installed_plugins.json known_marketplaces.json; do
    [ -f "$box/plugins/$f" ] && sed -i "s#$real/plugins#$box/plugins#g" "$box/plugins/$f"
  done
  # Skills: copy what each link points at (the shared drive, ~/.agents, ...).
  for entry in "$real"/skills/*; do
    [ -e "$entry" ] || continue
    name=$(basename "$entry")
    [ "$name" = synced ] && continue
    cp -rL "$entry" "$box/skills/$name" 2>/dev/null || true
  done
  # Settings without the sharing hook; MCP servers from ~/.claude.json.
  if [ -f "$real/settings.json" ]; then
    jq 'if .hooks.SessionStart then .hooks.SessionStart |= map(select(all(.hooks[]?; ((.command // "") | contains("claude-shared")) | not))) else . end' \
      "$real/settings.json" >"$box/settings.json"
  fi
  if [ -f "$HOME/.claude.json" ]; then
    jq '{mcpServers: (.mcpServers // {}), hasCompletedOnboarding: true}' "$HOME/.claude.json" >"$box/.claude.json"
  fi
  touch "$box/.seeded"
fi

export CLAUDE_CONFIG_DIR="$box" CLAUDE_SHARED_OFF=1
# claude-mem: own database and worker, so sandbox sessions never reach the
# shared memory.
export CLAUDE_MEM_DATA_DIR="$box/claude-mem" CLAUDE_MEM_WORKER_PORT="${CLAUDE_SANDBOX_MEM_PORT:-37787}"
exec "$CLAUDE_SANDBOX_CLAUDE" "$@"
