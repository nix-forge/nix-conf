{ lib, pkgs, ... }:
let
  nixIcon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
in
{
  options.programs.browserSuite.shared.search.commonEngines = lib.mkOption {
    type = lib.types.attrs;
    internal = true;
    readOnly = true;
    default = {
      nix-packages = {
        name = "Nix Packages";
        urls = [
          {
            template = "https://search.nixos.org/packages";
            params = [
              {
                name = "channel";
                value = "unstable";
              }
              {
                name = "query";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = nixIcon;
        definedAliases = [
          "@nixpkgs"
          "@np"
        ];
      };

      nixos-wiki = {
        name = "NixOS Wiki";
        urls = [
          {
            template = "https://wiki.nixos.org/w/index.php";
            params = [
              {
                name = "search";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = nixIcon;
        definedAliases = [
          "@nixos-wiki"
          "@nw"
        ];
      };

      home-manager-options = {
        name = "Home Manager Options";
        urls = [
          {
            template = "https://home-manager-options.extranix.com/";
            params = [
              {
                name = "release";
                value = "master";
              }
              {
                name = "query";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        iconMapObj."16" = "https://home-manager-options.extranix.com/images/favicon.png";
        definedAliases = [
          "@home-manager-options"
          "@hmo"
        ];
      };

      noogle = {
        name = "Noogle";
        urls = [
          {
            template = "https://noogle.dev/q";
            params = [
              {
                name = "term";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = "https://noogle.dev/favicon.ico";
        definedAliases = [
          "@noogle"
          "@ng"
        ];
      };

      github-repositories = {
        name = "GitHub Repositories";
        urls = [
          {
            template = "https://github.com/search";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
              {
                name = "type";
                value = "repositories";
              }
            ];
          }
        ];
        icon = "https://github.githubassets.com/favicons/favicon.svg";
        definedAliases = [
          "@github"
          "@gh"
        ];
      };

      github-code = {
        name = "GitHub Code";
        urls = [
          {
            template = "https://github.com/search";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
              {
                name = "type";
                value = "code";
              }
            ];
          }
        ];
        icon = "https://github.githubassets.com/favicons/favicon.svg";
        definedAliases = [
          "@github-code"
          "@ghc"
        ];
      };

      github-issues = {
        name = "GitHub Issues";
        urls = [
          {
            template = "https://github.com/search";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
              {
                name = "type";
                value = "issues";
              }
            ];
          }
        ];
        icon = "https://github.githubassets.com/favicons/favicon.svg";
        definedAliases = [
          "@github-issues"
          "@ghi"
        ];
      };
    };
  };
}
