{...}: {
  flake.nixosModules.users = {config, ...}: {
    users.users.${config.myConfig.primaryUser} = {
      isNormalUser = true;
      uid = config.myConfig.primaryUid;
      extraGroups = ["wheel" "networkmanager" "video" "audio" "seat" "uinput"];
    };
  };
}
