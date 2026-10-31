# Apps that CI runs (FY-0009): scripts/ with their tools. They use the Nix of
# the runner.
{ pkgs }:
let
  inherit (pkgs) lib;
  app = name: description: runtimeInputs: {
    type = "app";
    program = lib.getExe (
      pkgs.writeShellApplication {
        inherit name runtimeInputs;
        text = builtins.readFile ../scripts/${name}.sh;
      }
    );
    meta = { inherit description; };
  };
in
{
  check-reproducible = app "check-reproducible" "Rebuild own derivations, compare two streams" (
    with pkgs;
    [
      coreutils
      gawk
    ]
  );
  smoke = app "smoke" "Run the smoke tests of the image with docker" (
    with pkgs;
    [
      coreutils
      gawk
      gnugrep
      gnused
    ]
  );
  check-size = app "check-size" "Compare the image size with its budget" (
    with pkgs;
    [
      coreutils
      gawk
    ]
  );
}
