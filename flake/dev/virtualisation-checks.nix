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
              substitute ${../../modules/nixos/virtualisation/scripts/vm.sh.in} "$TMPDIR/vm" \
                --replace-fail '@sudo@' '${vmPackage.sudo}'
              substitute ${../../modules/nixos/virtualisation/scripts/windows-vm.sh.in} "$TMPDIR/windows-vm" \
                --replace-fail '@sudo@' '${windowsVmPackage.sudo}'
              grep -Fq '${desktop.security.wrapperDir}/sudo --non-interactive -- @privilegedControl@' "$TMPDIR/vm"
              grep -Fq '${desktop.security.wrapperDir}/sudo --non-interactive -- @privilegedControl@' "$TMPDIR/windows-vm"

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

              shellcheck -s bash ${../../modules/nixos/virtualisation/scripts/libvirt-workstation-setup.sh.in}
              shellcheck -s bash ${../../modules/nixos/virtualisation/scripts/libvirt-workstation-profile-guard.sh.in}
              shellcheck -s bash ${../../modules/nixos/virtualisation/scripts/libvirt-workstation-sleep-inhibitor-hook.sh.in}
              shellcheck -s bash ${../../modules/nixos/virtualisation/scripts/vm.sh.in}
              shellcheck -s bash ${../../modules/nixos/virtualisation/scripts/libvirt-windows-vm-control.sh.in}
              shellcheck -s bash ${../../modules/nixos/virtualisation/scripts/windows-vm.sh.in}
              shellcheck -s bash -e SC2034 ${../../modules/nixos/virtualisation/scripts/setup-windows-vm.sh.in}
              touch "$out"
            '';
      };
    };
}
