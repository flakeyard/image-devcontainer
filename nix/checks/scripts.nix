# The scripts of the apps and of .github pass shellcheck and tests/run.sh: the
# unit tests of the scripts, whose suites are at the paths of the scripts
# under tests/unit, and the static tests of the workflows in tests/unit/release
# and tests/unit/workflows, with the harness of the shell library that
# test.yaml pins. The smoke tests and their probes, which need a container
# engine, pass shellcheck.
{
  perSystem =
    {
      lib,
      pkgs,
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
              shellcheck
              yq-go
            ];
            source = lib.fileset.toSource {
              root = ../..;
              fileset = lib.fileset.unions [
                ../../.github
                ../../scripts
                ../../tests/bin
                ../../tests/lib
                ../../tests/run.sh
                ../../tests/unit
              ];
            };
            smoke = ../../tests/smoke;
          }
          ''
            cp -r "$source" source && cp -r ${shellLib} shell-lib
            chmod -R u+w source shell-lib
            cd source
            shellcheck scripts/*.sh scripts/*/*.sh tests/bin/* .github/scripts/*.sh .github/actions/*/*.sh
            shellcheck -x tests/run.sh tests/lib/*.sh tests/unit/*/*.sh
            shellcheck -x "$smoke"/*.sh "$smoke"/probes/*.sh
            # The sandbox has no /usr/bin/env.
            patchShebangs . ../shell-lib
            SHELL_LIB=$PWD/../shell-lib bash tests/run.sh
            touch $out
          '';
    };
}
