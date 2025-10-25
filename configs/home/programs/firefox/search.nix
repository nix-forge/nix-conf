profileName:
{ pkgs, ... }:
{
  programs.firefox.profiles.${profileName}.search = {
    force = true;

    default = "ddg";
    privateDefault = "ddg";

    engines = {
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
        icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
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
        icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
        definedAliases = [
          "@nixos-wiki"
          "@nw"
        ];
      };

      # TODO: Rename with nix prefix
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

      bing.metaData.hidden = true;
      ebay.metaData.hidden = true;
    };
  };
}
