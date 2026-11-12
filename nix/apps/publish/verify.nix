{
  pkgs,
  root,
  shellLib,
  ...
}:
{
  description = "Check the published image of a release";
  runtimeInputs = with pkgs; [
    crane
    gh
    gnugrep
    jq
  ];
  environment.PUBLISH_LIB = "${root + "/scripts/publish/lib.sh"}";
  environment.SHELL_LIB = "${shellLib}";
}
