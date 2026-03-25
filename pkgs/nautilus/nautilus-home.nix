# Home Manager symlinks for user-provided Nautilus Python extensions.
{ lib, ... }:

let
  sourceDir = ./nautilus-extensions;
  targetDir = ".local/share/nautilus-python/extensions";

  extensionFiles = builtins.attrNames (
    lib.filterAttrs (name: type:
      type == "regular" && lib.hasSuffix ".py" name
    ) (builtins.readDir sourceDir)
  );
in
{
  xdg.dataFile = builtins.listToAttrs (map (name: {
    name = "nautilus-python/extensions/${name}";
    value = {
      source = sourceDir + "/${name}";
    };
  }) extensionFiles);
}
