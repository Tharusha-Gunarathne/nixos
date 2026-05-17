{...}: {
  flake.nixosModules.keyboardLeds = {
    config,
    pkgs,
    lib,
    ...
  }: let
    # Loops over /sys/class/leds/, finds scroll-lock inputs, and writes
    # the current leds_value to brightness. Responds to SIGUSR1 to toggle.
    ledsDaemon = pkgs.writeShellScript "keyboard-leds-daemon" ''
      trap sigusr1_handler USR1

      sigusr1_handler() {
        if [ "$leds_value" -eq 1 ]; then
          leds_value=0
        else
          leds_value=1
        fi
      }

      led_folder="/sys/class/leds/"
      delay=0.2
      leds_value=1

      while true; do
        for inner_folder in "$led_folder"*; do
          name="$(basename "$inner_folder")"
          if echo "$name" | grep -q "input" && echo "$name" | grep -q "scrolllock"; then
            led_path="$inner_folder/brightness"
            if [ -f "$led_path" ]; then
              echo "$leds_value" > "$led_path" 2>/dev/null || true
            fi
          fi
        done
        sleep "$delay"
      done
    '';

    # Sends SIGUSR1 to the running daemon via systemctl (no sudo needed)
    ledsToggle = pkgs.writeShellScriptBin "keyboard-leds-toggle" ''
      echo "Toggling keyboard LEDs..."
      systemctl kill -s USR1 keyboard-leds.service
    '';
  in {
    systemd.services.keyboard-leds = {
      description = "Keyboard scroll-lock LED keeper for Wayland";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.coreutils}/bin/nice -n 19 ${pkgs.bash}/bin/bash ${ledsDaemon}";
        Restart = "on-failure";
        RestartSec = "3s";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "keyboard-leds.service" &&
            action.lookup("verb") == "kill" &&
            subject.isInGroup("wheel")) {
          return polkit.Result.YES;
        }
      });
    '';
    
    environment.systemPackages = [ ledsToggle ];
  };
}
