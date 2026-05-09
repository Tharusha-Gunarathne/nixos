{inputs, ...}: {
  flake.nixosModules.freeClaudeCode = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    fccPin = inputs.sources.sourcePins.freeClaudeCode;
    fccSrc = pkgs.fetchFromGitHub fccPin;
    proxyPort = 8082;

    defaultEnvTemplate = pkgs.writeText "free-claude-code-env-template" ''
      # ──────────────────────────────────────────────────────────
      #  Free Claude Code — proxy config
      #  Get your key: https://build.nvidia.com/settings/api-keys
      # ──────────────────────────────────────────────────────────

      NVIDIA_NIM_API_KEY=""

      # Browse models: https://build.nvidia.com/explore/discover
      # Get the model name by going to the model's page and looking for the get code field.
      MODEL="nvidia_nim/deepseek-ai/deepseek-v4-pro"

      # Local secret used by Claude Code to authenticate to this proxy.
      # Can be anything — it never leaves your machine.
      ANTHROPIC_AUTH_TOKEN="freecc"

      # Optional per-tier routing (blank = fall back to MODEL):
      MODEL_OPUS="nvidia_nim/z-ai/glm-5.1"
      MODEL_SONNET="nvidia_nim/minimaxai/minimax-m2.7"
      MODEL_HAIKU="nvidia_nim/deepseek-ai/deepseek-v4-flash"

      # Rate limiting (free NIM tier: ~40 req/min)
      PROVIDER_RATE_LIMIT=1
      PROVIDER_RATE_WINDOW=3

      # ENABLE_MODEL_THINKING=false
      # ENABLE_OPUS_THINKING=false
      # ENABLE_SONNET_THINKING=false
      # ENABLE_HAIKU_THINKING=false
    '';

    bootstrapScript = pkgs.writeShellScript "fcc-bootstrap" ''
      set -euo pipefail
      UV="${pkgs.uv}/bin/uv"
      WORK_DIR="$HOME/.local/share/free-claude-code"
      STATE_FILE="$WORK_DIR/.state"
      TARGET_REV="${fccPin.rev}"
      mkdir -p "$WORK_DIR"

      if [ -f "$STATE_FILE" ] && grep -qx "$TARGET_REV" "$STATE_FILE"; then
        exit 0
      fi

      echo "[fcc] Installing/updating free-claude-code (rev: $TARGET_REV)..."
      rm -rf "$WORK_DIR/src"
      mkdir -p "$WORK_DIR/src"
      ${pkgs.coreutils}/bin/cp -r "${fccSrc}/." "$WORK_DIR/src/"
      chmod -R u+w "$WORK_DIR/src"

      # ── Patch upstream bug: forward-reference in validator return type ──
      # settings.py has `-> Settings:` inside the Settings class body,
      # which fails at class definition time. Quoting it defers resolution.
      ${pkgs.gnused}/bin/sed -i \
        's/def check_nvidia_nim_api_key(self) -> Settings:/def check_nvidia_nim_api_key(self) -> "Settings":/' \
        "$WORK_DIR/src/config/settings.py"

      # Remove stale venv so uv doesn't fail with "already exists"
      rm -rf "$WORK_DIR/.venv"

      "$UV" venv \
        --python "${pkgs.python314}/bin/python3" \
        "$WORK_DIR/.venv"

      # Install runtime deps
      "$UV" pip install \
        --python "$WORK_DIR/.venv/bin/python" \
        --no-cache-dir \
        fastapi uvicorn httpx pydantic "python-dotenv" tiktoken \
        "pydantic-settings" openai loguru "markdown-it-py" "discord.py" \
        "python-telegram-bot"

      # Install build backend so --no-build-isolation works
      "$UV" pip install \
        --python "$WORK_DIR/.venv/bin/python" \
        --no-cache-dir \
        hatchling

      # Install the proxy package itself
      "$UV" pip install \
        --python "$WORK_DIR/.venv/bin/python" \
        --no-cache-dir \
        --no-build-isolation \
        "$WORK_DIR/src"

      echo "$TARGET_REV" > "$STATE_FILE"
      echo "[fcc] Bootstrap complete."
    '';

    proxyBin = pkgs.writeShellScriptBin "free-claude-code-proxy" ''
      set -euo pipefail
      CONFIG_FILE="$HOME/.config/free-claude-code/.env"
      WORK_DIR="$HOME/.local/share/free-claude-code"

      ${bootstrapScript}

      if [ -f "$CONFIG_FILE" ]; then
        set -a
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        set +a
      fi

      cd "$WORK_DIR/src"
      exec "$WORK_DIR/.venv/bin/uvicorn" server:app \
        --host 127.0.0.1 \
        --port ${toString proxyPort} \
        --log-level warning
    '';

    claudeFreeBin = pkgs.writeShellScriptBin "claude-free" ''
      CONFIG_FILE="$HOME/.config/free-claude-code/.env"
      AUTH_TOKEN="freecc"

      if [ -f "$CONFIG_FILE" ]; then
        _token=$(${pkgs.gnugrep}/bin/grep -E '^ANTHROPIC_AUTH_TOKEN=' "$CONFIG_FILE" \
          | ${pkgs.gnused}/bin/sed 's/^ANTHROPIC_AUTH_TOKEN=//' \
          | tr -d '"'"'" \
          | head -1)
        [ -n "$_token" ] && AUTH_TOKEN="$_token"
      fi

      exec env \
        ANTHROPIC_AUTH_TOKEN="$AUTH_TOKEN" \
        ANTHROPIC_BASE_URL="http://localhost:${toString proxyPort}" \
        ${pkgs.claude-code}/bin/claude "$@"
    '';
  in {
    home-manager.users.${username} = {
      lib,
      ...
    }: {
      home.packages = [proxyBin claudeFreeBin];

      home.activation.freeClaudeCodeConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        CONFIG_DIR="$HOME/.config/free-claude-code"
        CONFIG_FILE="$CONFIG_DIR/.env"
        mkdir -p "$CONFIG_DIR"
        if [ ! -f "$CONFIG_FILE" ]; then
          ${pkgs.coreutils}/bin/install -m 644 \
            "${defaultEnvTemplate}" \
            "$CONFIG_FILE"
          echo "[fcc] Created config at $CONFIG_FILE"
          echo "[fcc] Add your NVIDIA_NIM_API_KEY before starting the proxy."
        fi
      '';

      systemd.user.services.free-claude-code = {
        Unit = {
          Description = "Free Claude Code — NVIDIA NIM proxy for Claude Code";
          After = ["network-online.target"];
          Wants = ["network-online.target"];
        };
        Service = {
          Type = "simple";
          ExecStart = "${proxyBin}/bin/free-claude-code-proxy";
          Restart = "on-failure";
          RestartSec = "5s";
          StandardOutput = "journal";
          StandardError = "journal";
        };
        Install.WantedBy = ["default.target"];
      };
    };
  };
}