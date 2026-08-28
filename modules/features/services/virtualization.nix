{...}: {
  flake.nixosModules.virtualization = {
    config,
    pkgs,
    ...
  }: {
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
        vhostUserPackages = [pkgs.virtiofsd];
      };
    };

    programs.virt-manager.enable = true;

    users.users.${config.myConfig.primaryUser}.extraGroups = ["libvirtd" "kvm"];

    environment.variables.LIBVIRT_DEFAULT_URI = "qemu:///system";

    environment.systemPackages = with pkgs; [
      virtiofsd
      spice-gtk
      virtio-win
    ];

    # Declaratively (re)define + autostart the default NAT network,
    # so a fresh machine doesn't need the manual `virsh net-define` step.
    systemd.services.libvirt-default-network = {
      description = "Ensure libvirt default NAT network is defined and running";
      after = ["libvirtd.service"];
      requires = ["libvirtd.service"];
      wantedBy = ["multi-user.target"];
      path = [pkgs.libvirt];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = let
        networkXml = pkgs.writeText "default-network.xml" ''
          <network>
            <name>default</name>
            <forward mode="nat"/>
            <bridge name="virbr0" stp="on" delay="0"/>
            <ip address="192.168.122.1" netmask="255.255.255.0">
              <dhcp>
                <range start="192.168.122.2" end="192.168.122.254"/>
              </dhcp>
            </ip>
          </network>
        '';
      in ''
        if ! virsh net-info default >/dev/null 2>&1; then
          virsh net-define ${networkXml}
        fi
        virsh net-autostart default
        virsh net-start default || true
      '';
    };
  };
}