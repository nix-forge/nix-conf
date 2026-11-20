# Prowlarr cannot fetch its Cardigann catalog from the isolated service network.
# Pin the two definitions selected by the sealed desktop indexer catalog.
{
  inputs,
  myLib,
  pkgs,
  ...
}:
let
  fixes = import ../../../../../overlays/temporary { inherit inputs pkgs; };
  upstream = "https://raw.githubusercontent.com/Prowlarr/Indexers/ecede5c247d8e31fa156ff49a8921c78327c5b5d/definitions/v11";
  definitions = {
    nyaasi = pkgs.fetchurl {
      url = "${upstream}/nyaasi.yml";
      hash = "sha256-zqegbJOrvEbbsesNdNNN/sofJE8/f/4IodYzXWQAaHs=";
    };
    torrentdownload = fixes.apply "prowlarr-torrentdownload" (
      pkgs.fetchurl {
        url = "${upstream}/torrentdownload.yml";
        hash = "sha256-xINxyAzCK/7u9Yt8Y4ByfuigSaqu+e1Z2dorL0OksLc=";
      }
    );
  };

in
{
  homelab.apps.prowlarr.customDefinitions = {
    "nyaasi.yml" = definitions.nyaasi;
    "torrentdownload.yml" = definitions.torrentdownload;
  };

  # Retire only the targeted live repair once this definition is declarative.
  system.activationScripts.aurral-request-indexer-repair-cleanup.text =
    myLib.writers.renderBashText { inherit pkgs; }
      {
        name = "aurral-request-indexer-repair-cleanup-text.sh";
        text = ''
          # shellcheck shell=bash
          repair=/etc/systemd/system.control/prowlarr.service.d/97-aurral-requests.conf
          if [[ -f $repair && ! -L $repair ]]; then
            IFS= read -r header <"$repair" || true
            if [[ $header == '# Temporary Aurral request indexer repair.' ]]; then
              @pkgs_coreutils@/bin/rm -- "$repair"
              @pkgs_coreutils@/bin/rm -f -- /nix/var/nix/gcroots/aurral-request-indexer-repair
            fi
          fi
        '';
      }
      { pkgs_coreutils = pkgs.coreutils; };
}
