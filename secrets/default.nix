{ myLib }:
let
  collectAgeSecrets = myLib.dir.collectBySuffix "rekeyFile" ".age" "secrets";
in
{
  shared = collectAgeSecrets ./shared;
  systems = collectAgeSecrets ./systems;
  users = collectAgeSecrets ./users;
}
