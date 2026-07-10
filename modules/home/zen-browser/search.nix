{ pkgs, ... }: {
  programs.zen-browser.profiles.default.search = {
    force = true;

    default = "google-ai-mode";
    privateDefault = "ddg";

    engines = {
      google-ai-mode = {
        name = "Google AI Mode";
        urls = [
          {
            template = "https://www.google.com/ai";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = "https://www.google.com/favicon.ico";
        definedAliases = [
          "@google-ai"
          "@gai"
          "@ai"
        ];
      };

      perplexity-ai = {
        name = "Perplexity";
        urls = [
          {
            template = "https://www.perplexity.ai/search";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = "https://www.perplexity.ai/favicon.ico";
        definedAliases = [
          "@perplexity"
          "@perp"
          "@p"
        ];
      };

      chatgpt-thinking-search = {
        name = "ChatGPT";
        urls = [
          {
            template = "https://chatgpt.com/";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
              {
                name = "hints";
                value = "search,reason";
              }
            ];
          }
        ];
        icon = "https://chatgpt.com/favicon.ico";
        definedAliases = [
          "@chatgpt"
          "@gpt"
          "@cgpt"
        ];
      };

      youtube = {
        name = "YouTube";
        urls = [
          {
            template = "https://www.youtube.com/results";
            params = [
              {
                name = "search_query";
                value = "{searchTerms}";
              }
            ];
          }
        ];
        icon = "https://www.youtube.com/favicon.ico";
        definedAliases = [
          "@youtube"
          "@yt"
        ];
      };

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
          "@nhmo"
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
