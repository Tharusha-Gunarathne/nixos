{self, ...}: {
  flake.nixosModules.development = {
    pkgs,
    config,
    ...
  }: {
    imports = [
      self.nixosModules.gns3
      self.nixosModules.claudeSync
      self.nixosModules.python
      self.nixosModules.vscode
      self.nixosModules.zedEditor
      self.nixosModules.adb
      self.nixosModules.lamp
      self.nixosModules.neovim
    ];
    
    environment.systemPackages = with pkgs; [
      # Compilers / build toolchain
      gcc
      gnumake
      gdb
      pkg-config
      nil # nix language server
    ];

    home-manager.users.${config.myConfig.primaryUser} = {pkgs, ...}: {
      home.packages = with pkgs; [
        # Language runtimes / package managers
        uv
        nodejs
        bun
        devenv
        octaveFull
        go

        # IDEs
        jetbrains.webstorm
        jetbrains.phpstorm
        jetbrains.pycharm
        jetbrains.idea
        jetbrains.datagrip
        jetbrains.rust-rover
        antigravity-ide
        eclipses.eclipse-java

        # Dev-adjacent tooling
        gh
        postman
        firebase-tools
        devtoolbox
        nasm
        binutils
        
        # CLI tooling
        claude-code

        # Miscellaneous
        lmstudio
      ];
    };
  };
}