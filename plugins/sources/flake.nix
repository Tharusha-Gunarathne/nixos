{
  description = "Pinned external source registry";

  inputs = {
    modernz = {
      url = "github:Samillion/ModernZ/v0.3.1";
      flake = false;
    };

    spicetify-comfy = {
      url = "github:Comfy-Themes/Spicetify/32ff101e27cfd33d85b7cc587f7f95db6b2df8b0";
      flake = false;
    };
  };

  outputs = inputs: {
    sources = {
      inherit
        (inputs)
        modernz
        spicetify-comfy
        ;
    };

    releaseAssets = {
      lotion = {
        version = "1.5.0";
        url = "https://github.com/puneetsl/lotion/releases/download/v1.5.0/lotion_1.5.0_amd64.deb";
        sha256 = "031bgqfgnxwc00pir8ipjpfkxc5g50739h104fzhsqanza02sag8";
      };

      xdm = {
        version = "8.0.29";
        url = "https://github.com/subhra74/xdm/releases/download/8.0.29/xdman_gtk_8.0.29_amd64.deb";
        sha256 = "04cydd5i94qbnsi2535mswapng6hbwc567jhzbq8s715n0nvnn9n";
      };
    };
  };
}
