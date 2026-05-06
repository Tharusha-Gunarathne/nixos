{...}: {
  flake.nixosModules.lamp = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
  in {
    # Apache
    services.httpd = {
      enable = true;
      enablePHP = true;
      phpPackage = pkgs.php83;
      adminAddr = "admin@localhost";

      virtualHosts."localhost" = {
        documentRoot = "/var/www/html";
        extraConfig = ''
          <Directory "/var/www/html">
            Options Indexes FollowSymLinks
            AllowOverride All
            Require all granted
          </Directory>
        '';
      };
    };

    # MariaDB (MySQL drop-in)
    services.mysql = {
      enable = true;
      package = pkgs.mariadb;
      settings.mysqld = {
        bind-address = "127.0.0.1";
      };
    };

    # PHP extensions (add/remove as needed)
    services.httpd.phpOptions = ''
      extension=${pkgs.php83Extensions.pdo_mysql}/lib/php/extensions/pdo_mysql.so
      extension=${pkgs.php83Extensions.mysqli}/lib/php/extensions/mysqli.so
      extension=${pkgs.php83Extensions.mbstring}/lib/php/extensions/mbstring.so
      extension=${pkgs.php83Extensions.curl}/lib/php/extensions/curl.so
      extension=${pkgs.php83Extensions.zip}/lib/php/extensions/zip.so
    '';

    # Web root with correct permissions
    systemd.tmpfiles.rules = [
      "d /var/www/html 0755 wwwrun wwwrun -"
    ];

    # CLI tools available system-wide
    environment.systemPackages = with pkgs; [
      php83
      php83Packages.composer
      mariadb
    ];

    # Give primary user access to web root
    users.users.${username}.extraGroups = ["wwwrun"];
  };
}
