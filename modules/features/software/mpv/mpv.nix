{inputs, ...}: {
  flake.nixosModules.mpv = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;

    modernZPin = inputs.sources.sourcePins.modernz;
    modernZSrc = pkgs.fetchFromGitHub modernZPin;

    eisaMpvPin = inputs.sources.sourcePins.mpv-scripts-eisa01;
    eisaMpvSrc = pkgs.fetchFromGitHub eisaMpvPin;

    modernZOscConf = pkgs.runCommandLocal "modernz.conf" {} ''
      install -m 644 "${modernZSrc}/modernz.conf" "$out"
      chmod u+w "$out"
      sed -i '/^layout=/d; /^icon_theme=/d; /^icon_style=/d; /^nibbles_style=/d; /^scalewindowed=/d; /^scalefullscreen=/d' "$out"
      cat >> "$out" <<'EOF'

      # Local overrides
      layout=modern-compact
      icon_theme=material
      icon_style=mixed
      nibbles_style=gap

      # Local scaling override for HiDPI / large UI setups
      scalewindowed=0.65
      scalefullscreen=0.65
      EOF
    '';
  in {
    home-manager.users.${username} = {...}: {
      programs.mpv = {
        enable = true;
        config = {
          osc = "no";
          "osd-bar" = "no";
          gpu-api = "vulkan";
          ao = "pipewire";
          hwdec = "auto";
          sub-font-size = 60;
          subscale = 1.0;
          osd-font-size = 32;
          osd-scale = 1.0;
          sub-scale-by-window = "no";
        };
      };

      xdg.configFile = {
        # ModernZ themes
        "mpv/scripts/modernz.lua".source = "${modernZSrc}/modernz.lua";
        "mpv/fonts/modernz-icons.ttf".source = "${modernZSrc}/modernz-icons.ttf";
        "mpv/script-opts/modernz.conf".source = modernZOscConf;

        # Pause Indicator Lite
        "mpv/scripts/pause_indicator_lite.lua".source = "${modernZSrc}/extras/pause-indicator-lite/pause_indicator_lite.lua";
        "mpv/script-opts/pause_indicator_lite.conf".source = "${modernZSrc}/extras/pause-indicator-lite/pause_indicator_lite.conf";

        # Simple History - Eisa01's MPV scripts
        "mpv/scripts/SimpleHistory.lua".source = "${eisaMpvSrc}/scripts/SimpleHistory.lua";
        "mpv/script-opts/SimpleHistory.conf".source = "${eisaMpvSrc}/script-opts/SimpleHistory.conf";
      };

      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "video/mp4" = ["mpv.desktop"];
          "video/x-matroska" = ["mpv.desktop"]; # .mkv
          "video/mp2t" = ["mpv.desktop"]; # .ts
          "video/webm" = ["mpv.desktop"];
          "video/x-msvideo" = ["mpv.desktop"]; # .avi
          "video/quicktime" = ["mpv.desktop"]; # .mov
          "video/x-flv" = ["mpv.desktop"];
          "video/mpeg" = ["mpv.desktop"];
          "video/3gpp" = ["mpv.desktop"];
          "video/x-wmv" = ["mpv.desktop"];
          "video/ogg" = ["mpv.desktop"];
        };
      };
    };
  };
}
