{
  extensionUpdateUrl = "https://clients2.google.com/service/update2/crx";

  # Add or remove Chrome Web Store extension IDs here. macOS updates and loads
  # this complete set when Helium starts; NixOS installs it through policy.
  heliumExtensions = {
    sponsorBlock = "mnjggcdmjocbbbhaepdhchncahnbgone";
    bitwarden = "nngceckbapebfimnlniiiahkandclblb";
    karakeep = "kgcjekpmcjjogibpjebkhaanilehneje";
    refinedGitHub = "hlepfoohegkhhmjieoechaddaejaokhf";
  };
}
