{localConfig, ...}: {
  flake.nixosModules.git = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
    homeDir = "/home/${username}";

    # Must match the displayName derivation in noctalia.nix exactly — that's
    # the value actually written into settings.toml, so the redaction value
    # here has to be computed the same way or this filter silently misses it.
    capitalize = s:
      if s == ""
      then s
      else lib.toUpper (builtins.substring 0 1 s) + builtins.substring 1 (builtins.stringLength s - 1) s;

    configuredDisplayName = localConfig.user.display_name or "";
    displayName =
      if configuredDisplayName != ""
      then configuredDisplayName
      else lib.concatStringsSep "-" (map capitalize (lib.splitString "-" username));

    # Strips two kinds of volatile/personal content out of settings.toml
    # before git stages or diffs it:
    #   1. wallpaper.{default,last,monitors.*}.path — changes every time you
    #      pick a new wallpaper.
    #   2. Any literal occurrence of your real home dir / username / display
    #      name. The sync system writes real values into the repo's working
    #      file now (no templating layer), so this is the only thing keeping
    #      personal info out of git history.
    #
    # The real on-disk file is never touched by this — it only changes what
    # git sees when comparing/staging/committing.
    noctaliaSettingsCleanFilter = pkgs.writers.writePython3 "noctalia-settings-clean-filter" {
      libraries = [pkgs.python3Packages.tomlkit];
    } ''
      import sys
      import tomlkit

      PERSONAL_VALUES = {
          "${homeDir}": "REDACTED-HOME",
          "${username}": "REDACTED-USERNAME",
          "${displayName}": "REDACTED-DISPLAY-NAME",
      }

      text = sys.stdin.read()
      for real, placeholder in PERSONAL_VALUES.items():
          if real:
              text = text.replace(real, placeholder)

      doc = tomlkit.parse(text)

      wallpaper = doc.get("wallpaper")
      if wallpaper is not None:
          for key in ("default", "last"):
              section = wallpaper.get(key)
              if section is not None and "path" in section:
                  section["path"] = "REDACTED-BY-GIT-FILTER"
          monitors = wallpaper.get("monitors")
          if monitors is not None:
              for mon in monitors.values():
                  if "path" in mon:
                      mon["path"] = "REDACTED-BY-GIT-FILTER"

      sys.stdout.write(tomlkit.dumps(doc))
    '';
  in {
    home-manager.users.${username} = {...}: {
      programs.git = {
        enable = true;
        settings = {
          user = {
            name = localConfig.user.git_name;
            email = localConfig.user.git_email;
          };
          filter.noctalia-settings = {
            clean = "${noctaliaSettingsCleanFilter}";
            smudge = "cat";
            required = false;
          };
        };
      };
    };
  };
}
