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
  check-licenses =
    let
      # Identifiers of the licenses in nixpkgs that forbid redistribution.
      nonRedistributable = pkgs.writeText "non-redistributable-licenses" (
        lib.concatLines (
          lib.concatMap (
            license:
            # sbomnix names a license by its SPDX id or short name.
            lib.filter (id: id != null) [
              (license.spdxId or null)
              (license.shortName or null)
            ]
          ) (lib.filter (license: !(license.redistributable or true)) (lib.attrValues lib.licenses))
        )
      );
    in
    app'
      ''
        export NON_REDISTRIBUTABLE=${nonRedistributable}
        export CLOSURE=${image.expected}/closure
        export KNOWN_LICENSES=${
          pkgs.writeText "known-licenses.json" (
            builtins.toJSON (
              import ./licenses.nix {
                inherit pkgs;
                parts = import ./parts.nix { inherit pkgs; };
              }
            )
          )
        }
      ''
      "check-licenses"
      "Generate the SBOM and check the licenses of the image"
      (
        with pkgs;
        [
          coreutils
          gawk
          jq
          sbomnix
        ]
      );
  # Publication (FY-0027); the registry login must exist.
  platform-digest = app "platform-digest" "Stream the image and print its platform digest" (
    with pkgs;
    [
      coreutils
      crane
    ]
  );
  push-platform = app "push-platform" "Push the tested platform image by digest" (
    with pkgs;
    [
      coreutils
      crane
    ]
  );
  publish-index = app "publish-index" "Publish the manifest list and its release tag" (
    with pkgs;
    [
      coreutils
      crane
      gnugrep
      jq
      regclient
    ]
  );
  verify-published = app "verify-published" "Check the published image of a release" (
    with pkgs;
    [
      coreutils
      crane
      gh
      jq
    ]
  );
  sync-major = app "sync-major" "Point vX at the newest release of major X" (
    with pkgs;
    [
      coreutils
      crane
      gnugrep
    ]
  );
  # Weekly maintenance, not required (FY-0026, FY-0027).
  check-eol = app "check-eol" "Warn before the nixpkgs branch reaches its end of life" (
    with pkgs;
    [
      coreutils
      gnugrep
    ]
  );
  check-release-rebuild = app "check-release-rebuild" "Rebuild the newest release and compare" (
    with pkgs;
    [
      coreutils
      crane
      git
      gnugrep
      jq
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
