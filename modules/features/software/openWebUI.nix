{localConfig, ...}: {
  flake.nixosModules.openWebUI = {pkgs, ...}: let
    nim = localConfig.nvidia_nim;

    icon = pkgs.writeText "open-webui.svg" ''
      <svg width="48" height="48" viewBox="0 0 177 177" xmlns="http://www.w3.org/2000/svg">
        <circle cx="88.5" cy="88.5" r="88.5" fill="#1a1a1a"/>
        <path d="M122.8 48.4h16v79h-16z" fill="white"/>
        <circle cx="71.2" cy="87.5" r="39.1" fill="white"/>
        <circle cx="71.2" cy="87.5" r="23.4" fill="#1a1a1a"/>
      </svg>
    '';
  in {
    services.open-webui = {
      enable = true;
      port = 8080;
      host = "127.0.0.1";
      environment = {
        OPENAI_API_BASE_URL = "https://integrate.api.nvidia.com/v1";
        OPENAI_API_KEY = nim.api_key; # from .env.local
        WEBUI_AUTH = "False";
        DEFAULT_MODELS = nim.openwebui_default_model;
        SCARF_NO_ANALYTICS = "true";
        DO_NOT_TRACK = "true";
        ANONYMIZED_TELEMETRY = "false";
      };
    };

    # Prevent automatic startup — start manually when needed
    systemd.services.open-webui.wantedBy = pkgs.lib.mkForce [];

    home-manager.sharedModules = [
      {
        xdg.desktopEntries.open-webui = {
          name = "Open WebUI";
          comment = "Chat with AI models via NVIDIA NIM";
          exec = "xdg-open http://localhost:8080";
          icon = "${icon}";
          terminal = false;
          categories = ["Network" "Application"];
        };
      }
    ];
  };
}
