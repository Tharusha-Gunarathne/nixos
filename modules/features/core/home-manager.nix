{ ... }:
{
  flake.nixosModules.homeManager = { config, utils, ... }: {
    systemd.services."home-manager-${utils.escapeSystemdPath config.myConfig.primaryUser}" = {
      after = [ "dbus.service" "network-online.target" ];
      wants = [ "dbus.service" "network-online.target" ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "3s";
      };
    };
  };
}
