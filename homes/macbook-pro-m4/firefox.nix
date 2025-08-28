profileName:
{ ... }:
{
  programs.firefox.profiles.${profileName}.search.engines = {
    cornell-cs-courses = {
      name = "Cornell CS Courses";
      urls = [ { template = "https://www.cs.cornell.edu/courses/cs{searchTerms}/"; } ];
      definedAliases = [
        "@cornell-cs-courses"
        "@ccc"
      ];
    };
  };
}
