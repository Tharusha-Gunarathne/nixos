{localConfig, ...}: {
  flake.nixosModules.network = {lib, pkgs, ...}: let
    net = localConfig.network;
    hasStaticIp = net.static_ip != "";
  in {
    environment.systemPackages = with pkgs; [ iw pciutils ];
    
    networking.hostName = "nixos";
    networking.networkmanager.enable = true;
    networking.enableIPv6 = false;

    services.resolved.enable = true;

    networking.firewall.extraCommands = ''
      iptables -I INPUT   -i tun+ -j ACCEPT
      iptables -I FORWARD -i tun+ -j ACCEPT
      iptables -I FORWARD -o tun+ -j ACCEPT
    '';

    networking.interfaces.wlan0.ipv4.addresses = lib.optionals hasStaticIp [
      {
        address = net.static_ip;
        prefixLength = net.prefix_length;
      }
    ];

    networking.firewall.allowedTCPPorts = [
      80 # HTTP
      443 # HTTPS
      9090 # Cockpit
      9999 # private_app Server
      8081
      3000
    ];

    # Fix: recover wifi if it comes up greyed out after boot.
    # Uses `after` only (no bindsTo) so it never blocks multi-user.target.
    systemd.services.networkmanager-wifi-recover = {
      description = "Recover WiFi if NetworkManager missed wlan0 on boot";
      after = [
        "sys-subsystem-net-devices-wlan0.device"
        "NetworkManager.service"
      ];
      wants = ["sys-subsystem-net-devices-wlan0.device"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "wifi-recover" ''
          # Wait for NM to be fully settled
          sleep 3
          # If wifi radio shows as disabled or no devices, reload NM's wifi plugin
          WIFI_STATE=$(${pkgs.networkmanager}/bin/nmcli radio wifi 2>/dev/null || echo "unknown")
          if [ "$WIFI_STATE" = "disabled" ] || [ "$WIFI_STATE" = "unknown" ]; then
            ${pkgs.networkmanager}/bin/nmcli radio wifi on
            sleep 1
          fi
          # Check if NM can see the wifi device at all
          WIFI_DEV=$(${pkgs.networkmanager}/bin/nmcli -t -f DEVICE,TYPE dev 2>/dev/null | grep ":wifi" | cut -d: -f1)
          if [ -z "$WIFI_DEV" ]; then
            ${pkgs.systemd}/bin/systemctl try-restart NetworkManager.service
          fi
        '';
      };
    };
  };
}