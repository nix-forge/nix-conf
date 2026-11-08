# The primary news UI is ReactFlux over the Go Miniflux backend.
{ config, pkgs, ... }: {
  homelab.optional = {
    reactflux = {
      enable = true;
      package = pkgs.reactflux.override {
        defaultServerUrl = "https://news.${config.homelab.operations.lanHttps.domain}";
        readerDefaults = {
          articleListLayout = "card";
          coverDisplayMode = "banner";
          orderBy = "published_at";
          orderDirection = "desc";
          pageSize = 30;
          showCardSummary = true;
          summaryLines = 3;
          showEstimatedReadingTime = true;
          titleAlignment = "left";
          themeMode = "system";
          fontFamily = "system-ui";
          markReadOnScroll = false;
          openSourceOnCardClick = false;
          removeDuplicates = "url";
        };
      };
    };
    apps.miniflux.enable = true;
    miniflux = {
      adminCredentialsFile = config.nixSeal.templates.homelab-miniflux-admin-env.path;
      contentUpgrade = {
        revision = "article-quality-v2";
        backfillLimit = 30;
        stylesheet = builtins.readFile ./miniflux-reader.css;
        # Stop redundant/teaser-only subscriptions without deleting saved items.
        disabledFeeds = [
          "https://rss.nytimes.com/services/xml/rss/nyt/Science.xml"
          "https://arstechnica.com/science/feed/"
        ];
      };
      initialFeeds = [
        {
          url = "https://www.sciencenews.org/feed";
          crawler = true;
          scraperRules = "article > header figure, article .rich-text";
          rewriteRules = "add_dynamic_image";
          category = "Science";
        }
        {
          url = "https://www.esa.int/rssfeed/Our_Activities/Space_Science";
          # Mixed image briefs and articles: keep the publisher body intact.
          category = "Primary sources";
        }
        {
          url = "https://feeds.arstechnica.com/arstechnica/index";
          crawler = true;
          rewriteRules = "add_dynamic_image";
          category = "Technology";
        }
        {
          url = "https://www.pbs.org/newshour/feeds/rss/headlines";
          crawler = true;
          rewriteRules = "add_dynamic_image";
          category = "Broad reporting";
        }
        {
          url = "https://feeds.bbci.co.uk/news/world/rss.xml";
          crawler = true;
          scraperRules = "article";
          rewriteRules = "add_dynamic_image";
          category = "Broad reporting";
        }
        {
          url = "https://www.theguardian.com/world/rss";
          crawler = true;
          rewriteRules = "add_dynamic_image";
          category = "Broad reporting";
        }
        {
          url = "https://www.propublica.org/feeds/propublica/main";
          category = "Investigations";
        }
        {
          url = "https://themarkup.org/feeds/rss.xml";
          category = "Investigations";
        }
        {
          url = "https://www.quantamagazine.org/feed/";
          crawler = true;
          scraperRules = ".post > div > figure, .post__content.wysiwyg";
          rewriteRules = "add_dynamic_image";
          category = "Science";
        }
        {
          url = "https://www.technologyreview.com/feed/";
          category = "Technology";
        }
        {
          url = "https://www.theguardian.com/us/technology/rss";
          crawler = true;
          rewriteRules = "add_dynamic_image";
          category = "Technology";
        }
        {
          url = "https://theconversation.com/us/articles.atom";
          category = "Discovery";
        }
      ];
    };
  };

  homelab.operations.endpoints.news = {
    url = "https://news.${config.homelab.operations.lanHttps.domain}";
    healthUrl = "http://127.0.0.1:${toString config.homelab.optional.reactflux.port}/";
    description = "News reader with image cards, search and focused article reading";
  };

  services.miniflux.config = {
    BASE_URL = "https://miniflux.${config.homelab.operations.lanHttps.domain}";
    HTTPS = 1;
    TRUSTED_REVERSE_PROXY_NETWORKS = "127.0.0.1/32";
    WEBAUTHN = 1;
    MEDIA_PROXY_MODE = "all";
  };
}
