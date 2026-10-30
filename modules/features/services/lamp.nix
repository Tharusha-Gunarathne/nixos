{...}: {
  flake.nixosModules.lamp = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    php = pkgs.php83.buildEnv {
      extensions = {enabled, all}:
        pkgs.lib.unique (enabled ++ (with all; [pdo_mysql mysqli mbstring curl zip gd]));
    };
  in {
    # Apache
    services.httpd = {
      enable = true;
      enablePHP = true;
      phpPackage = php;
      adminAddr = "admin@localhost";

      virtualHosts."localhost" = {
        listen = [
          {
            ip = "127.0.0.1";
            port = 80;
          }
        ];
        documentRoot = "/var/www/html";
        extraConfig = ''
          <Directory "/var/www/html">
            Options Indexes FollowSymLinks
            AllowOverride All
            Require all granted
          </Directory>

          # adminer — general phpMyAdmin-equivalent, not tied to any one project
          Alias /adminer ${pkgs.adminer}/share/adminer
          <Directory "${pkgs.adminer}/share/adminer">
            DirectoryIndex adminer.php
            Options FollowSymLinks
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
      # Create per-project databases/users via adminer or the mysql CLI as needed —
      # ensureUsers can't set a usable password (anything here ends up world-readable
      # in /nix/store), so project credentials don't belong in this module.
    };

    # Web root with correct permissions
    systemd.tmpfiles.rules = [
      "d /var/www/html 0755 wwwrun wwwrun -"
    ];

    # CLI tools available system-wide
    environment.systemPackages = with pkgs; [
      php
      php83Packages.composer
      mariadb
      adminer
    ];

    # Give primary user access to web root
    users.users.${username}.extraGroups = ["wwwrun"];
  };
}
