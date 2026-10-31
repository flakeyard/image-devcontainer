# Apps that CI runs (FY-0009): scripts/ with their tools. They use the Nix of
# the runner.
{
  pkgs,
  parts,
  image,
}:
let
  inherit (pkgs) lib;

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

  # Licenses of the components sbomnix cannot match.
  knownLicenses = pkgs.writeText "known-licenses.json" (
    builtins.toJSON (import ./_licenses.nix { inherit pkgs parts; })
  );

  # mkApp: an app that runs scripts/NAME.sh with coreutils and runtimeInputs
  # on PATH and the variables of environment exported. Values are strings,
  # such as store paths.
  mkApp =
    {
      name,
      description,
      runtimeInputs ? [ ],
      environment ? { },
    }:
    {
      type = "app";
      program = lib.getExe (
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [ pkgs.coreutils ] ++ runtimeInputs;
          runtimeEnv = environment;
          text = builtins.readFile ../scripts/${name}.sh;
        }
      );
      meta = { inherit description; };
    };

  platformDigest = mkApp {
    name = "platform-digest";
    description = "Stream the image and print its platform digest";
    runtimeInputs = [ pkgs.crane ];
  };
in
{
  check-reproducible = mkApp {
    name = "check-reproducible";
    description = "Rebuild own derivations, compare two streams";
    runtimeInputs = [ pkgs.gawk ];
  };
  smoke = mkApp {
    name = "smoke";
    description = "Run the smoke tests of the image with docker";
    runtimeInputs = with pkgs; [
      binutils
      curl
      devcontainer
      findutils
      gawk
      gnugrep
      gnused
    ];
    environment = {
      EXPECTED = "${image.expected}";
      EDITOR_SERVER = "${import ./_editor-server.nix { inherit pkgs; }}";
    };
  };
  check-licenses = mkApp {
    name = "check-licenses";
    description = "Generate the SBOM and check the licenses of the image";
    runtimeInputs = with pkgs; [
      gawk
      jq
      sbomnix
    ];
    environment = {
      NON_REDISTRIBUTABLE = "${nonRedistributable}";
      CLOSURE = "${image.expected}/closure";
      CLOSURE_ROOT = "${image.closureRoot}";
      COMPLETE_LICENSES_JQ = "${../scripts/complete-licenses.jq}";
      SBOM_PROBLEMS_JQ = "${../scripts/sbom-problems.jq}";
      KNOWN_LICENSES = "${knownLicenses}";
    };
  };
  # Publication (FY-0027); the registry login must exist.
  platform-digest = platformDigest;
  # The same platform-digest computes the tested and the pushed digest.
  push-platform = mkApp {
    name = "push-platform";
    description = "Push the tested platform image by digest";
    runtimeInputs = [ pkgs.crane ];
    environment.PLATFORM_DIGEST = platformDigest.program;
  };
  publish-index = mkApp {
    name = "publish-index";
    description = "Publish the manifest list and its release tag";
    runtimeInputs = with pkgs; [
      crane
      gnugrep
      jq
      regclient
    ];
  };
  verify-published = mkApp {
    name = "verify-published";
    description = "Check the published image of a release";
    runtimeInputs = with pkgs; [
      crane
      gh
      jq
    ];
  };
  sync-major = mkApp {
    name = "sync-major";
    description = "Point vX at the newest release of major X";
    runtimeInputs = with pkgs; [
      crane
      gnugrep
    ];
  };
  # Weekly maintenance, not required (FY-0026, FY-0027).
  check-eol = mkApp {
    name = "check-eol";
    description = "Warn before the nixpkgs branch reaches its end of life";
    runtimeInputs = [ pkgs.gnugrep ];
  };
  check-release-rebuild = mkApp {
    name = "check-release-rebuild";
    description = "Rebuild the newest release and compare";
    runtimeInputs = with pkgs; [
      crane
      git
      gnugrep
      jq
    ];
  };
  check-size = mkApp {
    name = "check-size";
    description = "Compare the image size with its budget";
    runtimeInputs = [ pkgs.gawk ];
  };
}
