{localConfig, ...}: {
  flake.nixosModules.tailscale = {
    config,
    lib,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;

    # Read the auth key from .env.local if the [tailscale] section exists.
    # Falls back to "" so the module stays functional even without a key.
    tsConfig = localConfig.tailscale or {};
    authKey = tsConfig.auth_key or "";
    hasKey = authKey != "";
  in {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "client";

      # When an auth key is present, pass it via the authKeyFile mechanism.
      # NixOS writes the key to a tmpfs file at activation time and passes
      # --authkey=file:<path> to `tailscale up`, keeping it out of the store.
      authKeyFile = lib.mkIf hasKey (
        pkgs.writeText "tailscale-authkey" authKey
      );
    };

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };

    networking.firewall = {
      allowedUDPPorts = [41641];
      trustedInterfaces = ["tailscale0"];
    };

    # Write the key to /run (tmpfs) at activation so it never touches the
    # Nix store, then call `tailscale up` on first boot when a key is present.
    system.activationScripts.tailscaleAuthKey = lib.mkIf hasKey (
      lib.stringAfter ["etc"] ''
        set -euo pipefail
        KEY_FILE="/run/tailscale-authkey"
        install -m 0600 /dev/null "$KEY_FILE"
        printf '%s' "${authKey}" > "$KEY_FILE"
      ''
    );

    # One-shot service that runs `tailscale up --authkey=...` on first boot
    # (skips itself when Tailscale is already authenticated).
    systemd.services.tailscale-autoauth = lib.mkIf hasKey {
      description = "Tailscale one-shot auth on first boot";
      after = ["tailscaled.service" "network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Skip if already authenticated
        STATUS=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '.BackendState' 2>/dev/null || echo "unknown")

        if [ "$STATUS" = "Running" ]; then
          echo "[tailscale-autoauth] Already authenticated, skipping."
          exit 0
        fi

        echo "[tailscale-autoauth] Authenticating with key from .env.local..."
        ${pkgs.tailscale}/bin/tailscale up \
          --authkey="$(cat /run/tailscale-authkey)" \
          --timeout=30s
      '';
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "ts-up" ''
        exec sudo ${pkgs.tailscale}/bin/tailscale up "$@"
      '')
      (pkgs.writeShellScriptBin "ts-down" ''
        exec sudo ${pkgs.tailscale}/bin/tailscale down "$@"
      '')
      (pkgs.writeShellScriptBin "ts-status" ''
        exec ${pkgs.tailscale}/bin/tailscale status "$@"
      '')
      (pkgs.writeShellScriptBin "ts-ip" ''
        exec ${pkgs.tailscale}/bin/tailscale ip "$@"
      '')
      (pkgs.writeShellScriptBin "ts-logout" ''
        exec sudo ${pkgs.tailscale}/bin/tailscale logout "$@"
      '')
    ];

    home-manager.users.${username} = {...}: {
      xdg.desktopEntries.tailscale-admin = {
        name = "Tailscale Admin";
        comment = "Open Tailscale admin console";
        exec = "xdg-open https://login.tailscale.com/admin";
        icon = "network-vpn";
        terminal = false;
        categories = ["Network" "System"];
      };
    };
  };
}
