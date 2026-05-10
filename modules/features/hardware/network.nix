{localConfig, ...}: {
  flake.nixosModules.network = {lib, ...}: let
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

    # Only assign a static IP when one is set in .env.local
    networking.interfaces.wlan0.ipv4.addresses = lib.optionals hasStaticIp [
      {
        address = net.static_ip;
        prefixLength = net.prefix_length;
      }
    ];

    networking.firewall.allowedTCPPorts = [80 443 9090];
  };
}
