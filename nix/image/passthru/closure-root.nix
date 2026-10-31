# Refers to every path in the contents of the image: its closure is the
# image's store, which the SBOM describes.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.image.passthru.closureRoot = lib.mkOption {
        type = lib.types.package;
        description = "A file that refers to every path in the contents of the image.";
      };
      config.image.passthru.closureRoot = pkgs.writeText "image-closure-root" (
        lib.concatMapStringsSep "\n" toString config.image.contents
      );
    };
}
