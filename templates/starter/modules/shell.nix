{
  programs.bash = {
    enable = true;
    historyControl = [ "ignoreboth" ];
    shellAliases = {
      ll = "ls -lah";
      gs = "git status --short --branch";
    };
  };
}
