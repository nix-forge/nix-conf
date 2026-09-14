{ self, lib, ... }:
let
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];
  features = [
    {
      name = "Independent Home Manager starter";
      source = "templates/starter/flake.nix";
      platforms = systems;
      interface = "templates.starter";
      dependencies = "Nix; independent Nixpkgs and Home Manager 26.05 pins";
      state = "Generated configuration; activation must be explicitly chosen";
      validation = "Export extraction, native home/generated-config checks and x86 Linux console VM";
      guide = "first-configuration.md";
    }
    {
      name = "Apple silicon system example";
      source = "templates/darwin/flake.nix";
      platforms = [ "aarch64-darwin" ];
      interface = "templates.darwin";
      dependencies = "Native Apple silicon Mac; independent stable Nixpkgs and nix-darwin pins";
      state = "Build-only example; operating-system activation requires adaptation";
      validation = "Native system build and generated Zsh/plist check; no activation claim";
      guide = "darwin-example.md";
    }
    {
      name = "Graphical practice VM";
      source = "tests/public-guide/graphical-vm.nix";
      platforms = [ "x86_64-linux" ];
      interface = "packages.x86_64-linux.public-demo-vm";
      dependencies = "QEMU; Sway software rendering; disposable local console";
      state = "Practice disk remains separate from the host account";
      validation = "Graphical login, real terminal keybindings and generated Git behavior";
      guide = "graphical-demo.md";
    }
    {
      name = "Validation and performance records";
      source = "scripts/workstation_evidence.py";
      platforms = systems;
      interface = "workstation-evidence CLI and validationManifest";
      dependencies = "Git; Nix for system validation; native host for platform-specific evidence";
      state = "Private local receipts and logs; reviewed summaries may be shared";
      validation = "Source filtering, failed/skipped evidence, timeouts, process cleanup and comparison regressions";
      guide = "validation.md";
    }
    {
      name = "Git defaults";
      source = "modules/home/dev/git.nix";
      platforms = systems;
      interface = "Home Manager source-file import";
      dependencies = "Home Manager; libsecret on Linux or Keychain on macOS for credential storage";
      state = "Repositories and credential-backend data remain user-owned";
      validation = "public-guide-recipes; public consumer checks";
      guide = "git.md";
    }
    {
      name = "File search";
      source = "modules/home/shells/fzf.nix";
      platforms = systems;
      interface = "Home Manager source-file import";
      dependencies = "Home Manager; shell integration module for keybindings";
      state = "No application database; searched files remain user-owned";
      validation = "public-guide-recipes; public consumer checks";
      guide = "file-search.md";
    }
    {
      name = "Shell prompt";
      source = "modules/home/shells/starship.nix";
      platforms = systems;
      interface = "Home Manager source-file import";
      dependencies = "Home Manager; shell integration";
      state = "No persistent application state required";
      validation = "public-guide-recipes; public consumer checks";
      guide = "prompt.md";
    }
    {
      name = "Secure Boot preparation";
      source = "modules/nixos/boot/secure-boot.nix";
      platforms = [ "x86_64-linux" ];
      interface = "security.secureBootLanzaboote options";
      dependencies = "Lanzaboote flake input; UEFI; attended key enrollment and recovery";
      state = "Signing keys, ESP and recovery material require independent protection";
      validation = "Configuration contracts; physical enrollment and recovery remain operator checks";
      guide = "update-and-recover.md";
    }
    {
      name = "Application recovery drills";
      source = "modules/nixos/services/application-recovery/default.nix";
      platforms = [ "x86_64-linux" ];
      interface = "services.applicationRecovery.applications options";
      dependencies = "Provisioned backup repository; application-specific export and semantic checks";
      state = "Exports, backup repositories and drill receipts; live recovery remains operator-owned";
      validation = "Real SQLite/Restic fixture and NixOS lifecycle test; no live restore claimed";
      guide = "recovery-drills.md";
    }
    {
      name = "Service and backup health";
      source = "hosts/nixos/desktop/local/storage/health.nix";
      platforms = [ "x86_64-linux" ];
      interface = "hardware.storage.encryptedRoot.health options (desktop-local)";
      dependencies = "Desktop storage policy; operator-provided unattended notification command";
      state = "Freshness receipts and pending delivery state; notification acceptance is tested separately";
      validation = "Health collection, failed delivery retries and recovery transition fixtures";
      guide = "recovery-drills.md";
    }
    {
      name = "Windows guest";
      source = "modules/nixos/virtualisation/windows-vm.nix";
      platforms = [ "x86_64-linux" ];
      interface = "virtualisation.libvirtWorkstation.windowsVm options";
      dependencies = "libvirtWorkstation module; myLib; KVM; user-supplied Windows media";
      state = "Disk, firmware variables and virtual TPM must be recovered together";
      validation = "Domain XML and seed tests; installed Windows runtime requires the actual guest";
      guide = "features.md";
    }
  ];
  valid = lib.all (feature: builtins.pathExists (self.outPath + "/" + feature.source)) features;
in
{
  flake.featureCatalog =
    assert valid;
    {
      schema = 1;
      inherit features;
    };
  perSystem = { pkgs, ... }: {
    packages.feature-catalog = pkgs.writeText "feature-catalog.json" (
      builtins.toJSON self.featureCatalog
    );
    packages.feature-options =
      (pkgs.nixosOptionsDoc {
        options = {
          security.secureBootLanzaboote =
            self.nixosConfigurations.desktop.options.security.secureBootLanzaboote;
          services.applicationRecovery =
            self.nixosConfigurations.desktop.options.services.applicationRecovery;
          hardware.storage.encryptedRoot.health =
            self.nixosConfigurations.desktop.options.hardware.storage.encryptedRoot.health;
          virtualisation.libvirtWorkstation =
            self.nixosConfigurations.desktop.options.virtualisation.libvirtWorkstation;
        };
        warningsAreErrors = true;
        transformOptions =
          option:
          option
          // {
            declarations = map (
              declaration:
              "https://github.com/nix-forge/nix-conf/blob/main/"
              + lib.removePrefix (toString self.outPath + "/") (toString declaration)
            ) option.declarations;
          };
      }).optionsJSON;
  };
}
