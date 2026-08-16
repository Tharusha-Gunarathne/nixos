{...}: {
  flake.nixosModules.gaming = {pkgs, ...}: {
    # Steam + Proton
    programs.steam = {
      enable = true;
      gamescopeSession.enable = true;
      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      # Ships Proton-GE alongside Valve's own Proton builds in the
      # Steam Play compatibility tool list.
      extraCompatPackages = [pkgs.proton-ge-bin];
    };

    # CPU governor bump + I/O priority while a game is running
    programs.gamemode.enable = true;

    # Backend Steam's gamescopeSession uses; capSysNice lets it renice itself
    programs.gamescope = {
      enable = true;
      capSysNice = true;
    };

    environment.systemPackages = with pkgs; [
      # FPS/frametime/temp overlay. Not forced on globally — add
      # `mangohud %command%` to a game's Steam launch options to use it
      # per-game, or run `mangohud <binary>` for non-Steam stuff.
      mangohud

      # Non-Steam Windows game support (GOG/Epic/manual installs),
      # used by Faugus and by umu-launcher directly.
      umu-launcher
      wineWow64Packages.staging
      winetricks
      faugus-launcher
      lutris
      protonup-qt
    ];

    environment.sessionVariables = {
      # Lets Steam pick up manually-dropped custom Proton/Wine builds
      # in addition to the nix-provided extraCompatPackages above.
      STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
    };
  };
}
