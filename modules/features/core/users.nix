{...}: {
  flake.nixosModules.users = {
    config,
    lib,
    pkgs,
    ...
  }: {
    myConfig.username = lib.mkDefault "tharusha-gunarathne";

    users.users.${config.myConfig.username} = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = ["wheel" "networkmanager" "video" "audio" "seat"];
    };
  };
}
