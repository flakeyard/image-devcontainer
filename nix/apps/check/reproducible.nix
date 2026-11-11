{ pkgs, ... }:
{
  description = "Rebuild what the binary cache lacks, compare two streams";
  runtimeInputs = with pkgs; [
    gawk
    jq
  ];
  environment.IMAGE_LIB = "${../../../scripts/lib/image.sh}";
}
