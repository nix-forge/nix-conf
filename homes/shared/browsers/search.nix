_:
let
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

    cornell-cs-courses = {
      name = "Cornell CS Courses";
      urls = [ { template = "https://www.cs.cornell.edu/courses/cs{searchTerms}/"; } ];
      iconMapObj."16" = "https://www.cornell.edu/favicon.svg";
      definedAliases = [
        "@cornell-cs-courses"
        "@ccc"
      ];
    };
  };

  personalSearch = {
    default = "google-ai-mode";
    privateDefault = "ddg";
    engines = engines // {
      bing.metaData.hidden = true;
      ebay.metaData.hidden = true;
    };
  };
in
{
  programs.firefox.profiles.default.search = personalSearch;
  programs.zen-browser.profiles.default.search = personalSearch;
}
