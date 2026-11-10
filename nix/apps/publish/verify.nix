{ pkgs, ... }:
{
  description = "Check the published image of a release";
  runtimeInputs = with pkgs; [
    crane
    gh
    jq
  ];
  environment.PUBLISH_LIB = "${../../../scripts/publish/lib.sh}";
}
