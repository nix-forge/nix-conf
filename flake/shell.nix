{ self, ... }:
{
  perSystem =
    {
      pkgs,
      system,
      lib,
      ...
    }:
    let
      python = pkgs.callPackage ./python.nix { };
      inherit (python) python_with_pkgs python_path;
    in
    {
      devShells.default =
        let
          gitHooksShellHook = self.checks.${system}.git-hooks-check.shellHook;
          gitHooksEnabledPackages = self.checks.${system}.git-hooks-check.enabledPackages;

          # Make the library path
          lib_path = pkgs.lib.makeLibraryPath (
            with pkgs;
            [
              stdenv.cc.cc.lib
              openssl
            ]
          );
        in
        pkgs.mkShellNoCC {
          buildInputs = [
            python_with_pkgs
            pkgs.openssl
          ]
          ++ gitHooksEnabledPackages;
          packages = [ ];

          shellHook =
            let
              updatePath = old: new: "export ${old}=\"${new}\"";
              updateOldPath =
                oldEnvVar: newVarPath: append:
                lib.pipe oldEnvVar [
                  (x: (lib.optionals (!append) [ ("$" + x) ]) ++ newVarPath)
                  (x: (x ++ (lib.optionals append [ ("$" + oldEnvVar) ])))
                  (lib.strings.concatStringsSep ":")
                  (updatePath oldEnvVar)
                ];

              git_bin = lib.getExe pkgs.git;
              grep_bin = lib.getExe pkgs.ripgrep;
              gitExclude =
                ignorePath:
                let
                  git_exclude_path = "$(${git_bin} rev-parse --git-path info/exclude)";
                in
                "${git_bin} rev-parse --is-inside-work-tree >/dev/null 2>&1 && { ${grep_bin} -Fxq -- ${ignorePath} ${git_exclude_path} || echo ${ignorePath} >> ${git_exclude_path}; }";

              cwd = "$(pwd)";

              local_python_pkgs_dir_name = ".pip_packages";
              local_python_pkgs_dir = "${cwd}/${local_python_pkgs_dir_name}";
            in
            lib.concatStringsSep "\n" [
              ''
                # Augment the dynamic linker path
                ${updateOldPath "LD_LIBRARY_PATH" [ lib_path ] false}

                # Tells pip to put packages into $PIP_PREFIX instead of the usual locations.
                # See https://pip.pypa.io/en/stable/user_guide/#environment-variables.
                unset SOURCE_DATE_EPOCH
                ${updatePath "PIP_PREFIX" local_python_pkgs_dir}
                ${updateOldPath "PYTHONPATH" [
                  # Installed pip packages
                  "${local_python_pkgs_dir}/${python_with_pkgs.sitePackages}"
                  python_path
                ] true}
                ${updateOldPath "PATH" [ "${local_python_pkgs_dir}/bin" ] true}
                ${gitExclude (local_python_pkgs_dir_name + "/")}
              ''
              gitHooksShellHook
            ];
        };
    };
}
