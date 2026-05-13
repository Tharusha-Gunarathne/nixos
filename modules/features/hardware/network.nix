{localConfig, ...}: {
  flake.nixosModules.network = {lib, pkgs, ...}: let
    net = localConfig.network;
    hasStaticIp = net.static_ip != "";
  in {
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

    networking.firewall.allowedTCPPorts = [80 443 9090];

    # Fix: restart NetworkManager if wlan0 device appears after NM already started.
    # This resolves the intermittent "No Wi-Fi networks found" race condition on boot.
    systemd.services.networkmanager-wifi-recover = {
      description = "Restart NetworkManager when wlan0 appears late";
      bindsTo = ["sys-subsystem-net-devices-wlan0.device"];
      after = [
        "sys-subsystem-net-devices-wlan0.device"
        "NetworkManager.service"
      ];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl try-restart NetworkManager.service";
        # Give NM a moment to settle before checking
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      };
    };
  };
}
