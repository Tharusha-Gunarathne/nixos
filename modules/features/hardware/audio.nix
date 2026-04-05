{...}: {
  flake.nixosModules.audio = {...}: {
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };
  };
}
