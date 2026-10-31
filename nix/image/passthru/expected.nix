# What the smoke tests expect of the image.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.image) parts contents;
      inherit (config.image.config) environment metadata;
    in
    {
      options.image.passthru.expected = lib.mkOption {
        type = lib.types.package;
        description = "A directory of the files the smoke tests compare the image with.";
      };
      config.image.passthru.expected = pkgs.linkFarm "image-expected" {
        "nix.conf" = pkgs.writeText "nix.conf" parts.nixConf;
        "env" = pkgs.writeText "env" (lib.concatLines environment);
        "metadata" = pkgs.writeText "metadata" metadata;
        "nix-version" = pkgs.writeText "nix-version" parts.nix.version;
        # The store paths of the image: the closure the SBOM describes.
        "closure" = pkgs.runCommand "image-closure" {
          info = pkgs.closureInfo { rootPaths = contents; };
        } "cp $info/store-paths $out";
        # The library directories nix-ld serves besides glibc.
        "foreign-libraries" = pkgs.writeText "foreign-libraries" (
          lib.concatMapStrings (l: "${lib.getLib l}/lib\n") parts.foreign.libraries
        );
      };
    };
}
