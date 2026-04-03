{ self, ... }: {
  flake.nixosModules.users = { config, lib, ... }: {
    myConfig.username = lib.mkDefault "tharusha-gunarathne";

    users.users.${config.myConfig.username} = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" "video" "audio" "seat" ];
      shell = pkgs.fish;
    };
  };
}
