# The scripts of the apps and of .github pass tests/run.sh: the unit tests of
# the scripts, whose suites are at the paths of the scripts under tests/unit,
# and the static tests of the workflows in tests/unit/release and
# tests/unit/workflows, with the harness of the shell library that test.yaml
# pins. atom-shell lints every script, the smoke tests among them
# (checks.shell).
{
  perSystem =
    {
      lib,
      pkgs,
      root,
      shellLib,
      ...
    }:
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
              gnused
              jq
              yq-go
            ];
            source = lib.fileset.toSource {
              inherit root;
              fileset = lib.fileset.unions [
                (root + "/.github")
                (root + "/scripts")
                (root + "/tests/bin")
                (root + "/tests/lib")
                (root + "/tests/run.sh")
                (root + "/tests/unit")
              ];
            };
          }
          ''
            cp -r "$source" source && cp -r ${shellLib} shell-lib
            chmod -R u+w source shell-lib
            cd source
            # The sandbox has no /usr/bin/env.
            patchShebangs . ../shell-lib
            SHELL_LIB=$PWD/../shell-lib bash tests/run.sh
            touch $out
          '';
    };
}
