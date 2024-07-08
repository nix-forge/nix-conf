{ pkgs, config, ... }:
let
  profile = "${config.home.username}.default";

  extensions = {
    rycee = pkgs.nur.repos.rycee.firefox-addons;
    bandithedoge = pkgs.nur.repos.bandithedoge.firefoxAddons;
    slaier = pkgs.nur.repos.slaier.firefox-addons;
  };
in
{
  programs.firefox.profiles.${profile} = {
    extensions = with extensions; [
      ### BASICS ###
      rycee.darkreader
      # rycee.tree-style-tab
      # rycee.tab-stash
      # rycee.translate-web-pages

      ### PERFORMANCE ###
      # rycee.auto-tab-discard

      ### BLOCKING ###
      # Enable "Annoyances" lists in uBO instead
      # rycee.i-dont-care-about-cookies
      rycee.user-agent-string-switcher
      # rycee.gaoptout
      # rycee.clearurls
      # rycee.disconnect
      # rycee.libredirect

      ### GITHUB ###
      # bandithedoge.gitako
      # bandithedoge.sourcegraph
      # rycee.enhanced-github
      rycee.refined-github
      # rycee.lovely-forks
      # rycee.octolinker
      rycee.octotree

      ### YOUTUBE ###
      rycee.sponsorblock
      # rycee.return-youtube-dislikes
      rycee.enhancer-for-youtube

      ### NEW INTERNET ###
      # rycee.ipfs-companion

      ### FIXES ###
      # rycee.open-in-browser
      # rycee.no-pdf-download
      # rycee.don-t-fuck-with-paste

      ### UTILITIES ###
      rycee.video-downloadhelper
      # rycee.export-tabs-urls-and-titles
      # rycee.markdownload
      # rycee.flagfox
      # rycee.keepassxc-browser
      rycee.wappalyzer
      # slaier.dictionary-anywhere
    ];
  };
}
