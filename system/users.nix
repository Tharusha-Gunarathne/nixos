# Primary user account and group memberships.
{ config, lib, pkgs, username, ... }:

{
  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "seat"
    ];
  };
}
