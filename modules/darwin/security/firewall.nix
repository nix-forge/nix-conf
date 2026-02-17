{
  networking.applicationFirewall = {
    enable = true;
    blockAllIncoming = false;

    allowSignedApp = false;
    allowSigned = true;

    enableStealthMode = true;
  };
}
