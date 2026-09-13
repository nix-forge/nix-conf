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
      setupScript = desktop.systemd.services.libvirt-workstation-setup.serviceConfig.ExecStart;
      profileGuard = desktop.virtualisation.libvirtd.hooks.qemu."10-workstation-profile-guard";
      sleepInhibitorHook = desktop.virtualisation.libvirtd.hooks.qemu."20-workstation-sleep-inhibitor";
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
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        virtualisation-generated-artifacts =
          assert lib.all (entry: entry.assertion) desktop.assertions;
          pkgs.runCommand "virtualisation-generated-artifacts"
            {
              nativeBuildInputs = [
                pkgs.gnugrep
                pkgs.libxml2
                pkgs.powershell
                pkgs.shellcheck
              ];
            }
            ''
              # Nix store sudo has no setuid bit. Exercise the generated entry
              # points that must call the wrapper installed by NixOS activation.
              grep -Fq '${desktop.security.wrapperDir}/sudo --non-interactive -- ' ${vmPackage}/bin/vm
              grep -Fq '${desktop.security.wrapperDir}/sudo --non-interactive -- ' ${windowsVmPackage}/bin/windows-vm

              test "$(xmllint --xpath 'string(/domain/os/type/@machine)' ${runtimeDomain})" = pc-q35-10.2
              test "$(xmllint --xpath 'string(/domain/devices/disk[@device="disk"]/target/@bus)' ${runtimeDomain})" = scsi
              test "$(xmllint --xpath 'count(/domain/devices/disk[target/@bus="scsi"]/driver/@iothread)' ${runtimeDomain})" = 0
              test "$(xmllint --xpath 'string(/domain/devices/controller[@type="scsi"][@model="virtio-scsi"]/driver/@iothread)' ${runtimeDomain})" = 1
              test "$(xmllint --xpath 'count(/domain/devices/disk[@device="cdrom"])' ${runtimeDomain})" = 0
              test "$(xmllint --xpath 'count(/domain/devices/interface)' ${runtimeDomain})" = 2
              test "$(xmllint --xpath 'string(/domain/devices/disk[@device="disk" and target/@dev="sda"]/target/@bus)' ${installerDomain})" = sata
              test "$(xmllint --xpath 'count(/domain/devices/disk[@device="cdrom"])' ${installerDomain})" = 3

              ! grep -Eq '__[A-Z0-9_]+__' ${windowsBootstrap}
              ! grep -Eq '__[A-Z0-9_]+__' ${windowsBaseline}
              grep -Eq "^[$]RecipeFingerprint = '[0-9a-f]{64}'$" ${windowsBootstrap}
              grep -Eq "^[$]RecipeFingerprint = '[0-9a-f]{64}'$" ${windowsBaseline}
              test "$(grep -E "^[$]RecipeFingerprint = '[0-9a-f]{64}'$" ${windowsBootstrap})" = \
                "$(grep -E "^[$]RecipeFingerprint = '[0-9a-f]{64}'$" ${windowsBaseline})"

              pwsh -NoLogo -NoProfile -NonInteractive -Command '
                $failed = $false
                foreach ($path in @(
                  "${windowsBootstrap}",
                  "${windowsBaseline}"
                )) {
                  $tokens = $null
                  $errors = $null
                  [System.Management.Automation.Language.Parser]::ParseFile(
                    $path,
                    [ref]$tokens,
                    [ref]$errors
                  ) | Out-Null
                  if ($errors.Count -gt 0) {
                    $failed = $true
                    $errors | ForEach-Object { Write-Error "''${path}:$($_.Message)" }
                  }
                }
                if ($failed) { exit 1 }
              '

              shellcheck -s bash ${setupScript}
              shellcheck -s bash ${profileGuard}
              shellcheck -s bash ${sleepInhibitorHook}
              shellcheck -s bash ${vmPackage}/bin/vm
              shellcheck -s bash ${windowsSetupScript}
              shellcheck -s bash ${windowsVmPackage}/bin/windows-vm
              shellcheck -s bash -e SC2034 ${setupWindowsVmPackage}/bin/setup-windows-vm
              touch "$out"
            '';
      };
    };
}
