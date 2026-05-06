{...}: {
  flake.nixosModules.network = {...}: {
    networking.hostName = "nixos";
    networking.networkmanager.enable = true;
    networking.enableIPv6 = false;

    services.resolved.enable = true;

    networking.firewall.extraCommands = ''
      iptables -I INPUT -i tun+ -j ACCEPT
      iptables -I FORWARD -i tun+ -j ACCEPT
      iptables -I FORWARD -o tun+ -j ACCEPT
    '';

    networking.interfaces.wlan0.ipv4.addresses = [{
      address = "192.168.1.100";
      prefixLength = 24;
    }];

    # Firewall — open HTTP/HTTPS if needed
    networking.firewall.allowedTCPPorts = [80 443 9090];
  };
}
