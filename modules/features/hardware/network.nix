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
  };
}
