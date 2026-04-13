{...}: {
  flake.nixosModules.mpv = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.username;
    modernZSrc = pkgs.fetchFromGitHub {
      owner = "Samillion";
      repo = "ModernZ";
      rev = "v0.3.1";
      sha256 = "0711blyif7r2dfxxax9vsv0wp4rrwys8dk3jqay8c19arq9qly64";
    };

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
        };
      };

      xdg.configFile = {
        "mpv/scripts/modernz.lua".source = "${modernZSrc}/modernz.lua";
        "mpv/fonts/modernz-icons.ttf".source = "${modernZSrc}/modernz-icons.ttf";
        "mpv/script-opts/modernz.conf".source = modernZOscConf;
      };
    };
  };
}
