{ self, ... }: {
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      desktop = self.nixosConfigurations.desktop.config;
      memoryVariant =
        (self.nixosConfigurations.desktop.extendModules {
          modules = [
            { virtualisation.libvirtWorkstation.windowsVm.resources.currentMemoryMiB = lib.mkForce 6144; }
          ];
        }).config;
      invalidMemoryVariant =
        (self.nixosConfigurations.desktop.extendModules {
          modules = [
            { virtualisation.libvirtWorkstation.windowsVm.resources.currentMemoryMiB = lib.mkForce 12288; }
          ];
        }).config;
      memoryVariantTriggers = memoryVariant.systemd.services.libvirt-windows-vm-setup.restartTriggers;
      setupScript = desktop.systemd.services.libvirt-workstation-setup.serviceConfig.ExecStart;
      profileGuard = desktop.virtualisation.libvirtd.hooks.qemu."10-workstation-profile-guard";
      sleepInhibitorHook = desktop.virtualisation.libvirtd.hooks.qemu."20-workstation-sleep-inhibitor";
      sleepInhibitorLauncher = builtins.head (
        lib.splitString " "
          desktop.systemd.services."libvirt-workstation-sleep-inhibit@".serviceConfig.ExecStart
      );
      windowsSetupScript = desktop.systemd.services.libvirt-windows-vm-setup.serviceConfig.ExecStart;
      windowsTriggers = desktop.systemd.services.libvirt-windows-vm-setup.restartTriggers;
      runtimeDomain = builtins.elemAt windowsTriggers 0;
      installerDomain = builtins.elemAt windowsTriggers 1;
      windowsBootstrap = builtins.elemAt windowsTriggers 2;
      windowsBaseline = builtins.elemAt windowsTriggers 3;
      findPackage =
        name:
        lib.findFirst (
          package: lib.getName package == name
        ) (throw "${name} package is missing") desktop.environment.systemPackages;
      vmPackage = findPackage "vm";
      windowsVmPackage = findPackage "windows-vm";
      setupWindowsVmPackage = findPackage "setup-windows-vm";
      runtimeConfiguration = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.unions [
          ../../homes
          ../../hosts
          ../../modules
        ];
      };
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        windows-vm-memory =
          assert
            desktop.virtualisation.libvirtWorkstation.windowsVm.resources.currentMemoryMiB
            == desktop.virtualisation.libvirtWorkstation.windowsVm.resources.memoryMiB;
          assert lib.any (
            item:
            !item.assertion && item.message == "windowsVm.resources.currentMemoryMiB must not exceed memoryMiB."
          ) invalidMemoryVariant.assertions;
          pkgs.runCommand "windows-vm-memory" { nativeBuildInputs = [ pkgs.libxml2 ]; } ''
            test "$(xmllint --xpath 'string(/domain/memory)' ${builtins.elemAt memoryVariantTriggers 0})" = 8192
            test "$(xmllint --xpath 'string(/domain/currentMemory)' ${builtins.elemAt memoryVariantTriggers 0})" = 6144
            test "$(xmllint --xpath 'string(/domain/currentMemory)' ${builtins.elemAt memoryVariantTriggers 1})" = 8192
            touch "$out"
          '';
        native-application-services =
          assert !desktop.virtualisation.docker.enable;
          assert !desktop.virtualisation.docker.rootless.enable;
          assert !desktop.virtualisation.podman.enable;
          assert !desktop.virtualisation.containerd.enable;
          assert desktop.virtualisation.oci-containers.containers == { };
          assert desktop.containers == { };
          pkgs.runCommand "native-application-services" { nativeBuildInputs = [ pkgs.ripgrep ]; } (
            (import ../../lib/templates/text.nix) ./scripts/native-application-services.sh {
              inherit runtimeConfiguration;
            }
          );
        virtualisation-generated-artifacts =
          pkgs.runCommand "virtualisation-generated-artifacts"
            {
              nativeBuildInputs = [
                pkgs.gnugrep
                pkgs.libxml2
                pkgs.powershell
                pkgs.shellcheck
              ];
            }
            (
              (import ./../../lib/templates/text.nix) ./scripts/virtualisation-generated-artifacts.sh {
                parserScript = ./scripts/parse-generated-artifacts.ps1;
                desktop_security_wrapperDir = desktop.security.wrapperDir;
                inherit vmPackage;
                inherit windowsVmPackage;
                inherit runtimeDomain;
                inherit installerDomain;
                inherit windowsBootstrap;
                inherit windowsBaseline;
                inherit setupScript;
                inherit profileGuard;
                inherit sleepInhibitorHook;
                inherit sleepInhibitorLauncher;
                inherit windowsSetupScript;
                inherit setupWindowsVmPackage;
              }
            );
      };
    };
}
