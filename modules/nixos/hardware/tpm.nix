{ pkgs, ... }: {
  security.tpm2 = {
    # This module is selected only by systems with a TPM 2.0 device. Enable
    # the NixOS TPM stack, including its udev ownership and persistent FAPI
    # storage setup, but do not enroll disk-unlock or login credentials here.
    # Those policies bind to a specific threat model and belong to the host.
    enable = true;
    applyUdevRules = true;

    # Modern kernels expose /dev/tpmrm0, their in-kernel TPM resource manager.
    # Prefer it over the legacy userspace abrmd daemon: it avoids a second D-Bus
    # service, has a smaller failure surface, and works for TPM tools, FAPI, and
    # PKCS#11 consumers through the standard resource-managed device.
    abrmd.enable = false;

    tctiEnvironment = {
      enable = true;
      interface = "device";
      deviceConf = "/dev/tpmrm0";
    };

    # Keep FAPI on the same explicit, resource-managed kernel interface rather
    # than relying on its environment-dependent TCTI auto-discovery order.
    fapi.tcti = "device:/dev/tpmrm0";

    # Expose the PKCS#11 provider for applications that deliberately create
    # non-exportable TPM-backed keys. No keys are generated automatically.
    pkcs11.enable = true;
  };

  # Keep the supported diagnostic/enrollment CLI available without exposing
  # implementation libraries and daemons redundantly in every user's PATH.
  environment.systemPackages = with pkgs; [ tpm2-tools ];
}
