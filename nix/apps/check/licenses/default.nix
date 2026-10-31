{ config, pkgs, ... }:
let
  inherit (config.packages) image;
  inherit (config.image) parts;
  # Licenses of the components sbomnix cannot match.
  knownLicenses = pkgs.writeText "known-licenses.json" (
    builtins.toJSON (import ./known.nix { inherit pkgs parts; })
  );
in
{
  description = "Generate the SBOM and check the licenses of the image";
  runtimeInputs = with pkgs; [
    gawk
    jq
    sbomnix
  ];
  environment = {
    NON_REDISTRIBUTABLE = "${import ./non-redistributable.nix { inherit pkgs; }}";
    CLOSURE = "${image.expected}/closure";
    CLOSURE_ROOT = "${image.closureRoot}";
    COMPLETE_LICENSES_JQ = "${../../../../scripts/check/licenses/complete.jq}";
    SBOM_PROBLEMS_JQ = "${../../../../scripts/check/licenses/problems.jq}";
    KNOWN_LICENSES = "${knownLicenses}";
  };
}
