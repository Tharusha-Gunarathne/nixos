{...}: {
  flake.nixosModules.adb = {config, pkgs, ...}: let
    username = config.myConfig.primaryUser;
  in {
    environment.systemPackages = with pkgs; [
      android-tools
    ];
    users.users.${username}.extraGroups = ["adbusers"];
  };
}
