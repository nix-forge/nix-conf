_:
let
  dailyExtensions = {
    karakeep = {
      id = "addon@karakeep.app";
      slug = "karakeep";
      defaultArea = "navbar";
    };

    refinedGitHub = {
      id = "{a4c4eda4-fb84-4a84-b4a1-f7c1cbf2a1ad}";
      slug = "refined-github-";
    };

    simplifyJobs = {
      id = "sabre@simplify.jobs";
      slug = "simplify-jobs";
    };

    sponsorBlock = {
      id = "sponsorBlocker@ajay.app";
      slug = "sponsorblock";
    };

    ublockOrigin = {
      id = "uBlock0@raymondhill.net";
      slug = "ublock-origin";
      privateBrowsing = true;
      defaultArea = "navbar";
    };
  };
in
{
  programs.browserSuite.extensions = {
    shared.bitwarden = {
      id = "{446900e4-71c2-419f-a6a7-df9c091e268b}";
      slug = "bitwarden-password-manager";
      mode = "required";
      privateBrowsing = true;
      defaultArea = "navbar";
    };

    firefox = builtins.mapAttrs (_: extension: extension // { mode = "allowed"; }) dailyExtensions // {
      multiAccountContainers = {
        id = "@testpilot-containers";
        slug = "multi-account-containers";
        mode = "allowed";
        defaultArea = "navbar";
      };
    };

    # Browser policy permits these add-ons, while each profile owns whether
    # they are installed. This keeps a minimal Shopping profile possible.
    zen = builtins.mapAttrs (_: extension: extension // { mode = "allowed"; }) dailyExtensions;
  };
}
