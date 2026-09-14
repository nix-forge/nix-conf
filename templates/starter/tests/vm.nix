''
  start_all()
  machine.wait_for_unit("multi-user.target")
  machine.wait_for_unit("home-manager-learner.service")
  machine.succeed("su - learner -c 'test $(git config --global init.defaultBranch) = main'")
  machine.succeed("su - learner -c 'test $(git config --global pull.ff) = only'")
  machine.succeed("su - learner -c 'git init ~/practice && cd ~/practice && git st' | grep 'No commits yet on main'")
  machine.succeed("su - learner -c \"bash -ic 'alias gs'\" | grep 'git status --short --branch'")
  machine.succeed("su - learner -c 'starship module character' | grep '>'")
  machine.fail("su - learner -c 'git config --global user.email'")
''
