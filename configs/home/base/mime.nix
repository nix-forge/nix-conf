{
  browser ? [ "firefox.desktop" ],
  editor ? [
    "code.desktop"
    "code-insiders.desktop"
  ],
# imageViewer ? [ "gimp.desktop" ],
# videoPlayer ? [ "vlc.desktop" ],
}:
{ ... }:
{
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # Applications
      "application/pdf" = browser;
      "applicaiton/json" = editor;
      "text/html" = browser;
      "text/xml" = browser;
      "text/plain" = editor;
      "application/xml" = browser;
      "application/xhtml+xml" = browser;
      "application/xhtml_xml" = browser;
      "application/rdf+xml" = browser;
      "application/rss+xml" = browser;
      "application/x-extension-htm" = browser;
      "application/x-extension-html" = browser;
      "application/x-extension-shtml" = browser;
      "application/x-extension-xht" = browser;
      "application/x-extension-xhtml" = browser;
      "application/x-wine-extension-ini" = editor;

      # define default applications for some url schemes.
      "x-scheme-handler/about" = browser; # open `about:` url with `browser`
      "x-scheme-handler/ftp" = browser; # open `ftp:` url with `browser`
      "x-scheme-handler/http" = browser;
      "x-scheme-handler/https" = browser;
      # https://github.com/microsoft/vscode/issues/146408
      "x-scheme-handler/vscode" = [ "code-url-handler.desktop" ]; # open `vscode://` url with `code-url-handler.desktop`
      "x-scheme-handler/vscode-insiders" = [ "code-insiders-url-handler.desktop" ]; # open `vscode-insiders://` url with `code-insiders-url-handler.desktop`
    };
  };
}
