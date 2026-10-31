{ pkgs, ... }:
{
  description = "Stream the image and print its platform digest";
  runtimeInputs = [ pkgs.crane ];
}
