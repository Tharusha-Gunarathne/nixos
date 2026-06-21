{...}: {
  flake.nixosModules.python = {
    config,
    ...
  }: {
    home-manager.users.${config.myConfig.primaryUser} = {pkgs, ...}: {
      home.packages = with pkgs; [
        (python314.withPackages (ps:
          with ps; [
            pip
            jupyterlab
            sympy
          ]))
      ];
    };
  };
}
