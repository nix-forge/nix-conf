{ pkgs, ... }: {
  security.tpm2 = {
    # This module is selected only by systems with a TPM 2.0 device. Enable
    # the NixOS TPM stack, including its udev ownership and persistent FAPI
    # storage setup, but do not enroll disk-unlock or login credentials here.
    # Those policies bind to a specific threat model and belong to the host.
    enable = true;
    applyUdevRules = true;

    # Use NixOS's userspace resource manager. It serializes stateful TPM
    # access across clients and is the TCTI selected below for tools and
    # PKCS#11 consumers.
    abrmd.enable = true;

    tctiEnvironment = {
      enable = true;
      interface = "tabrmd";
    };

    # Expose the PKCS#11 provider for applications that deliberately create
    # non-exportable TPM-backed keys. No keys are generated automatically.
    pkcs11.enable = true;
  };

  # Keep the supported diagnostic/enrollment CLI available without exposing
  # implementation libraries and daemons redundantly in every user's PATH.
  environment.systemPackages = with pkgs; [ tpm2-tools ];
}
