{
  description = "Noctalia Independent Plugin Registry";

  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };
  
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # NOCTALIA MAIN
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NOCTALIA PLUGINS
    # Each plugin tracks its own version in its own lockfile entry
    fancy-audiovisualizer = {
      url = "github:noctalia-dev/noctalia-plugins?dir=fancy-audiovisualizer";
      flake = false;
    };

    kde-connect = {
      url = "github:noctalia-dev/noctalia-plugins?dir=kde-connect";
      flake = false;
    };

    keybind-cheatsheet = {
      url = "github:noctalia-dev/noctalia-plugins?dir=keybind-cheatsheet";
      flake = false;
    };

    niri-auto-tile = {
      url = "github:noctalia-dev/noctalia-plugins?dir=niri-auto-tile";
      flake = false;
    };

    polkit-agent = {
      url = "github:noctalia-dev/noctalia-plugins?dir=polkit-agent";
      flake = false;
    };

    network-manager-vpn = {
      url = "github:noctalia-dev/noctalia-plugins?dir=network-manager-vpn";
      flake = false;
    };

    screen-toolkit = {
      url = "github:noctalia-dev/noctalia-plugins?dir=screen-toolkit";
      flake = false;
    };

    monique = {
      url = "github:noctalia-dev/noctalia-plugins?dir=monique";
      flake = false;
    };

    wallcards = {
      url = "github:noctalia-dev/noctalia-plugins?dir=wallcards";
      flake = false;
    };

    usb-drive-manager = {
      url = "github:noctalia-dev/noctalia-plugins?dir=usb-drive-manager";
      flake = false;
    };

    port-monitor = {
      url = "github:noctalia-dev/noctalia-plugins?dir=port-monitor";
      flake = false;
    };
  };

  outputs = inputs: {
    noctalia-main = inputs.noctalia;

    plugins = {
      # Add every plugin name here
      inherit
        (inputs)
        fancy-audiovisualizer
        kde-connect
        keybind-cheatsheet
        niri-auto-tile
        polkit-agent
        network-manager-vpn
        screen-toolkit
        monique
        wallcards
        usb-drive-manager
        port-monitor
        ;
    };
  };
}
