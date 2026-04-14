{...}: {
  flake.nixosModules.users = {
    config,
    lib,
    pkgs,
    ...
  }: {
    users.users.${config.myConfig.primaryUser} = {
      isNormalUser = true;
      uid = config.myConfig.primaryUid;
      extraGroups = ["wheel" "networkmanager" "video" "audio" "seat"];
    };
  };
}
