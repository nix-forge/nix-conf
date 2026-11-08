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
      mode = "normal";
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
      mode = "normal";
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

    firefox =
      builtins.mapAttrs (
        _: extension: extension // { mode = extension.mode or "allowed"; }
      ) dailyExtensions
      // {
        multiAccountContainers = {
          id = "@testpilot-containers";
          slug = "multi-account-containers";
          mode = "allowed";
          defaultArea = "navbar";
        };
      };

    # Other add-ons remain optional. uBlock and Refined GitHub install in every
    # profile and can still be disabled where a profile needs different behavior.
    zen = builtins.mapAttrs (
      _: extension: extension // { mode = extension.mode or "allowed"; }
    ) dailyExtensions;
  };
}
