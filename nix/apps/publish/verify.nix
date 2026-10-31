{ pkgs, ... }:
{
  description = "Check the published image of a release";
  runtimeInputs = with pkgs; [
    crane
    gh
    jq
  ];
}
