# Apps that CI runs (FY-0009): scripts/ with their tools. They use the Nix of
# the runner.
{ pkgs }:
let
  inherit (pkgs) lib;
  image = import ./image.nix {
    inherit pkgs;
    parts = import ./parts.nix { inherit pkgs; };
  };
  # prologue: shell code run before the script, such as fixed paths.
  app' = prologue: name: description: runtimeInputs: {
    type = "app";
    program = lib.getExe (
      pkgs.writeShellApplication {
        inherit name runtimeInputs;
        text = prologue + builtins.readFile ../scripts/${name}.sh;
      }
    );
    meta = { inherit description; };
  };
  app = app' "";
in
{
  check-reproducible = app "check-reproducible" "Rebuild own derivations, compare two streams" (
    with pkgs;
    [
      coreutils
      gawk
    ]
  );
  smoke =
    app'
      ''
        export EXPECTED=${image.expected}
        export EDITOR_SERVER=${import ./editor-server.nix { inherit pkgs; }}
      ''
      "smoke"
      "Run the smoke tests of the image with docker"
      (
        with pkgs;
        [
          binutils
          coreutils
          curl
          devcontainer
          findutils
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
