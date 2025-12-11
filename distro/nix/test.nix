{
  testers,
  modules,
  homeModule,
  writeShellScriptBin,
}:
let
  script = writeShellScriptBin "dms-basic-test" ''
    set -eu

    export XDG_CONFIG_HOME=''${XDG_CONFIG_HOME:-$HOME/.config}
    systemctl status dms.service --no-pager
  '';
in
testers.nixosTest {
  name = "dms-vm";

  nodes.machine = {
    environment.systemPackages = [ script ];
    imports = modules;

    programs.dankMaterialShell = {
      enable = true;
      greeter = {
        enable = true;
      };
    };
    users.users = {
      fake = {
        createHome = true;
        isNormalUser = true;
      };
    };
    programs.niri.enable = true;

    networking.networkmanager.enable = true;
    services = {
      xserver.enable = true;
      greetd = {
        enable = true;
        settings.default_session = {
          command = "sh -c 'exec niri-session'";
          user = "fake";
        };
      };
      displayManager = {
        autoLogin.enable = true;
        autoLogin.user = "fake";
      };
    };

    home-manager = {
      sharedModules = [ homeModule ];

      users.fake =
        { lib, pkgs, ... }:
        {
          home.stateVersion = "23.11";
          programs.dankMaterialShell = {
            enable = true;
            systemd.enable = true;
          };
        };
    };
    virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
  };

  testScript = ''
    # Boot:
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("nix-daemon.socket")

    # Wait for greetd autologin and user session
    machine.wait_for_unit("greetd.service")
    machine.wait_for_unit("user@1000.service")

    # Wait for DMS service to start and create config directory
    machine.wait_until_succeeds("systemctl --user -M fake@ status dms.service", 30)
    machine.wait_until_succeeds("test -e /home/fake/.config/DankMaterialShell", 30)

    # Run tests:
    machine.succeed("su - fake -c dms-basic-test")
  '';
}
