{
  description = "Pinned external source registry";

  outputs = _: {
    sourcePins = {
      modernz = {
        owner = "Samillion";
        repo = "ModernZ";
        rev = "ee54d5836c5618d0eae6458f7897fce415721d50";
        hash = "sha256-xHiKE84qBYa8wnLMhrTnOZPLwdY7ddW7ayIfFz1dIRw=";
      };

      spicetify-comfy = {
        owner = "Comfy-Themes";
        repo = "Spicetify";
        rev = "32ff101e27cfd33d85b7cc587f7f95db6b2df8b0";
        hash = "sha256-sqvmSXJMLE2in/cB8ZIJE/t4J5D0PKRddWECdYJjgX0=";
      };

      mpv-scripts-eisa01 = {
        owner = "Eisa01";
        repo = "mpv-scripts";
        rev = "b9e63743a858766c9cc7a801d77313b0cecdb049";
        hash = "sha256-XuFvCBOIiLncgsDZJJjU/qSSJJ5SfNF16pIJjIWUJ+A=";
      };

      # SDDM themes - CRITICAL
      qylock = {
        owner = "Darkkal44";
        repo = "qylock";
        rev = "6d676217daef421e1d4abdc99a9307c60ed0d49b";
        hash = "sha256-Qq+0hvSMJOmOhzqZet0SOi3N3PMCGd+GvlMArF7t8n0=";
      };

      # rEFInd themes - CRITICAL
      refindRegularDark = {
        owner = "m3h3d1ha2an";
        repo = "refind-regular-dark";
        rev = "2683ab842c19bd334331276a48a2029f55267cd1";
        hash = "sha256-GrTrFy+PmEh6M3hQgAJWJfnqjiwOgHGkvQatB9P1wds=";
      };
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
