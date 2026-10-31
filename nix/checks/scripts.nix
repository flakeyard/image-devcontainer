# The scripts of the apps and of .github pass shellcheck and their unit
# tests, whose suites are at the paths of the scripts under tests/unit.
{
  perSystem =
    { pkgs, ... }:
    {
      checks.scripts =
        pkgs.runCommand "script-tests"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              gawk
              git
              gnugrep
              jq
              shellcheck
            ];
            scripts = ../../scripts;
            stubs = ../../tests/bin;
            unit = ../../tests/unit;
            # A store path name cannot start with a period.
            github = builtins.path {
              name = "github";
              path = ../../.github;
            };
          }
          ''
            shellcheck "$scripts"/*.sh "$scripts"/*/*.sh "$stubs"/* "$github"/scripts/*.sh "$github"/actions/*/*.sh
            shellcheck -x "$unit"/lib.sh "$unit"/*/*.sh
            # The sandbox has no /usr/bin/env.
            cp -r "$scripts" scripts && cp -r "$stubs" stubs && cp -r "$github" github
            chmod -R u+w scripts stubs github
            patchShebangs scripts stubs github
            for suite in "$unit"/{check,publish}/*.sh; do
              SCRIPTS=$PWD/scripts STUBS=$PWD/stubs bash "$suite"
            done
            for suite in "$unit"/release/*.sh; do
              SCRIPTS=$PWD/github STUBS=$PWD/stubs bash "$suite"
            done
            touch $out
          '';
    };
}
