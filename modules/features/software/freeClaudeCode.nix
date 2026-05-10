{inputs, localConfig, ...}: {
  flake.nixosModules.freeClaudeCode = {
    config,
    pkgs,
    ...
  }: let
    username   = config.myConfig.primaryUser;
    fccPin     = inputs.sources.sourcePins.freeClaudeCode;
    fccSrc     = pkgs.fetchFromGitHub fccPin;
    nim        = localConfig.nvidia_nim;
    proxyPort  = nim.fcc_proxy_port;

    # Env template is now generated from localConfig values so defaults are
    # pre-populated on a fresh install; the user can still edit ~/.config/free-claude-code/.env
    defaultEnvTemplate = pkgs.writeText "free-claude-code-env-template" ''
      # ──────────────────────────────────────────────────────────
      #  Free Claude Code — proxy config
      #  Get your key: https://build.nvidia.com/settings/api-keys
      # ──────────────────────────────────────────────────────────

      NVIDIA_NIM_API_KEY="${nim.api_key}"

      # Browse models: https://build.nvidia.com/explore/discover
      MODEL="${nim.fcc_model_default}"

      # Local secret used by Claude Code to authenticate to this proxy.
      ANTHROPIC_AUTH_TOKEN="${nim.fcc_auth_token}"

      # Optional per-tier routing (blank = fall back to MODEL):
      MODEL_OPUS="${nim.fcc_model_opus}"
      MODEL_SONNET="${nim.fcc_model_sonnet}"
      MODEL_HAIKU="${nim.fcc_model_haiku}"

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
      ${pkgs.gnused}/bin/sed -i \
        's/def check_nvidia_nim_api_key(self) -> Settings:/def check_nvidia_nim_api_key(self) -> "Settings":/' \
        "$WORK_DIR/src/config/settings.py"

      rm -rf "$WORK_DIR/.venv"

      "$UV" venv \
        --python "${pkgs.python314}/bin/python3" \
        "$WORK_DIR/.venv"

      "$UV" pip install \
        --python "$WORK_DIR/.venv/bin/python" \
        --no-cache-dir \
        fastapi uvicorn httpx pydantic "python-dotenv" tiktoken \
        "pydantic-settings" openai loguru "markdown-it-py" "discord.py" \
        "python-telegram-bot"

      "$UV" pip install \
        --python "$WORK_DIR/.venv/bin/python" \
        --no-cache-dir \
        hatchling

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
      AUTH_TOKEN="${nim.fcc_auth_token}"

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
          echo "[fcc] Edit NVIDIA_NIM_API_KEY in $CONFIG_FILE if needed."
        fi
      '';

      systemd.user.services.free-claude-code = {
        Unit = {
          Description = "Free Claude Code — NVIDIA NIM proxy for Claude Code";
          After        = ["network-online.target"];
          Wants        = ["network-online.target"];
        };
        Service = {
          Type           = "simple";
          ExecStart      = "${proxyBin}/bin/free-claude-code-proxy";
          Restart        = "on-failure";
          RestartSec     = "5s";
          StandardOutput = "journal";
          StandardError  = "journal";
        };
        # Install.WantedBy = ["default.target"];
      };
    };
  };
}
