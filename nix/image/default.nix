# The image (FY-0005): a script that streams it as a docker archive. Each
# piece is a module of this directory; this file puts them in their order.
{
  perSystem =
    { config, lib, ... }:
    let
      inherit (config) image;
    in
    {
      # The image as a script that streams a docker archive to stdout.
      packages.image = image.dockerTools.streamLayeredImage {
        name = "image-devcontainer";
        # Not a registry tag: the release workflow publishes by digest.
        tag = "build";
        maxLayers = 100;
        includeNixDB = true;
        inherit (image) contents;
        passthru = { inherit (image.passthru) closureRoot expected; };
        # Paragraphs: directories, files outside the home directory, files in
        # it. The text names the layer it builds, and the image config shows
        # that name, so the text stays as it is.
        extraCommands = lib.concatStringsSep "\n" [
          image.filesystem.directories
          (image.filesystem.etc + image.parts.foreign.links)
          image.filesystem.home
        ];
        fakeRootCommands = image.filesystem.ownership;
        config = image.config.process // {
          Env = image.config.environment;
          Labels = image.config.labels;
        };
      };
    };
}
