# The labels of the image. The same for every commit; version and commit are
# annotations of the manifest list (FY-0027).
{
  perSystem =
    { config, lib, ... }:
    {
      options.image.config.labels = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "The labels of the image config.";
      };
      config.image.config.labels = {
        "devcontainer.metadata" = config.image.config.metadata;
        "org.opencontainers.image.source" = "https://github.com/flakeyard/image-devcontainer";
        "org.opencontainers.image.description" =
          "Dev container image with multi-user Nix, direnv and nix-direnv";
        "org.opencontainers.image.licenses" = "MIT";
      };
    };
}
