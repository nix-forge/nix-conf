{
  programs.firefox.profiles.default.search.engines = {
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
}
