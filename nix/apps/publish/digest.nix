{ pkgs, root, ... }:
{
  description = "Stream the image and print its platform digest";
  runtimeInputs = [ pkgs.crane ];
  environment.IMAGE_LIB = "${root + "/scripts/lib/image.sh"}";
}
