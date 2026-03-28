{
  boot.kernelModules = [ "uhid" ];
  security.tpm2 = {
    enable = true;
    applyUdevRules = true;
    abrmd.enable = true;
    tctiEnvironment.enable = true;
    pkcs11.enable = true;
  };
}
