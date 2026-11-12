{ pkgs, root, ... }:
{
  description = "Rebuild what the binary cache lacks, compare two streams";
  runtimeInputs = with pkgs; [
    gawk
    jq
  ];
  environment.IMAGE_LIB = "${root + "/scripts/lib/image.sh"}";
}
