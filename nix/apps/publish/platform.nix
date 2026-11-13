{
  config,
  pkgs,
  root,
  ...
}:
{
  description = "Push the tested platform image by digest";
  runtimeInputs = [ pkgs.crane ];
  # The same publish-digest computes the tested and the pushed digest.
  environment.PUBLISH_DIGEST = config.apps.publish-digest.program;
  environment.PUBLISH_LIB = "${root + "/scripts/publish/lib.sh"}";
}
