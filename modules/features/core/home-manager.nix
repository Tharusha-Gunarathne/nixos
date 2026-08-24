{ ... }:
{
  flake.nixosModules.homeManager = { ... }: {
    systemd.services."home-manager-tharusha\\x2dgunarathne" = {
      after = [ "dbus.service" "network-online.target" ];
      wants = [ "dbus.service" "network-online.target" ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "3s";
      };
    };
  };
}