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

      # Declared at system level (not relying on flake nixConfig, which is
      # only a *suggestion* unless --accept-flake-config is passed or the
      # prompt was already accepted interactively once). This guarantees
      # these caches are always trusted for nixos-rebuild, nh, etc.
      substituters = [
        "https://cache.nixos.org"
        "https://vicinae.cachix.org"
        "https://niri.cachix.org"
        "https://noctalia.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
        "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
        "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      ];
    };

    nixpkgs.config.allowUnfree = true;

    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    systemd.settings.Manager = {
      DefaultTimeoutStopSec = "15s";
    };

    systemd.services.systemd-logind.restartIfChanged = false;
    systemd.services.display-manager.restartIfChanged = false;

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
        token="$(${pkgs.python3}/bin/python3 -c 'import sys, tomllib; cfg = tomllib.load(open(sys.argv[1], "rb")); g = cfg.get("github") or {}; t = (g.get("access_token") or "") if isinstance(g, dict) else ""; print(t.strip() if isinstance(t, str) else "")' "$ENV_FILE")"
      fi
    
      if [ -n "$token" ]; then
        ${pkgs.coreutils}/bin/install -d -m 0755 /etc/nix
    
        tmp="$(${pkgs.coreutils}/bin/mktemp)"
        umask 077
        printf '%s\n' "access-tokens = github.com=$token" > "$tmp"
        ${pkgs.coreutils}/bin/install -m 0644 "$tmp" "$OUT_FILE"
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      else
        ${pkgs.coreutils}/bin/rm -f "$OUT_FILE"
      fi
    
      # Restart nix-daemon so it picks up the updated token file
      if ${pkgs.systemd}/bin/systemctl is-active --quiet nix-daemon; then
        ${pkgs.systemd}/bin/systemctl restart nix-daemon || true
      fi
    '';

    nix.extraOptions = ''
      !include /etc/nix/access-tokens.conf
      warn-dirty = false
      keep-going = true
      log-lines = 20
    '';
    
    system.stateVersion = "25.11";
  };

  perSystem = {pkgs, ...}: {
    formatter = pkgs.alejandra;
  };
}
