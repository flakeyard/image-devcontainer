{ pkgs, ... }:
{
  description = "Stream the image and print its platform digest";
  runtimeInputs = [ pkgs.crane ];
  environment.IMAGE_LIB = "${../../../scripts/lib/image.sh}";
}
