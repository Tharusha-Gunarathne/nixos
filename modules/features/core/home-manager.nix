{ ... }:
{
  flake.nixosModules.homeManager = { ... }: {
    # Ensure the home-manager activation service doesn't race ahead of
    # dbus / network / user-session setup at boot. Without this it's only
    # ordered after nix-daemon.socket, which is enough on a manual
    # `nix-switch` but not at cold boot when noctaliaPluginsEnable's
    # dbus calls and noctaliaSpotifySetup's network calls can fire before
    # those services are actually up — causing an intermittent FAILED unit
    # with no useful error in the journal.
    systemd.services."home-manager-tharusha-gunarathne" = {
      after = [ "dbus.service" "network-online.target" "systemd-user-sessions.service" ];
      wants = [ "dbus.service" "network-online.target" ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "3s";
      };
    };
  };
}