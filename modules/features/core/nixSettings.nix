{...}: {
  flake.nixosModules.nixSettings = {
    config,
    lib,
    pkgs,
    ...
  }: {
    nix.settings = {
      trusted-users = ["root" config.myConfig.primaryUser];
      experimental-features = ["nix-command" "flakes"];
      auto-optimise-store = true;
    };
    
    nixpkgs.config.allowUnfree = true;
    
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    
    nix.extraOptions = ''
      !include /etc/nix/access-tokens.conf
      warn-dirty = false
      keep-going = true
      log-lines = 20
    '';

    systemd.settings.Manager = {
      DefaultTimeoutStopSec = "15s";
    };

    # If a GitHub access token is present in ${config.myConfig.repoRoot}/.env.local
    # (TOML), write /etc/nix/access-tokens.conf so Nix can use it for fetching.
    #
    # This runs at activation time so the token doesn't need to be stored in the
    # Nix store via NixOS options.
    system.activationScripts.nixAccessTokens = lib.stringAfter ["etc"] ''
      set -euo pipefail

      REPO_ROOT="${config.myConfig.repoRoot}"
      ENV_FILE="$REPO_ROOT/.env.local"
      OUT_FILE="/etc/nix/access-tokens.conf"

      token=""

      if [ -f "$ENV_FILE" ]; then
        token="$(${pkgs.python3}/bin/python3 -c 'import sys, tomllib; cfg = tomllib.load(open(sys.argv[1], "rb")); g = cfg.get("github") or {}; t = (g.get("access-token") or "") if isinstance(g, dict) else ""; print(t.strip() if isinstance(t, str) else "")' "$ENV_FILE")"
      fi

      if [ -n "$token" ]; then
        ${pkgs.coreutils}/bin/install -d -m 0755 /etc/nix

        tmp="$(${pkgs.coreutils}/bin/mktemp)"
        umask 077
        printf '%s\n' "access-tokens = github.com=$token" > "$tmp"
        ${pkgs.coreutils}/bin/install -m 0600 "$tmp" "$OUT_FILE"
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      else
        ${pkgs.coreutils}/bin/rm -f "$OUT_FILE"
      fi
    '';

    system.stateVersion = "25.11";
  };

  perSystem = {pkgs, ...}: {
    formatter = pkgs.alejandra;
  };
}
