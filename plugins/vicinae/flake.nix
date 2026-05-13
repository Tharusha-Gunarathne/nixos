{
  description = "Vicinae Independent Plugin Registry";

  inputs = {
    # VICINAE MAIN
    vicinae.url = "github:vicinaehq/vicinae";

    # VICINAE EXTENSIONS
    vicinae-extensions.url = "github:vicinaehq/extensions";
  };

  outputs = inputs: {
    vicinae-main = inputs.vicinae;
    vicinae-extensions = inputs.vicinae-extensions;
  };
}