# The environment of the container.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.image.parts) foreign;
    in
    {
      options.image.config.environment = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "The variables of the image config, in order.";
      };
      config.image.config.environment = [
        "LANG=C.UTF-8"
        # Root's PATH; the entrypoint and /etc/bashrc add dev's profile for dev.
        "PATH=/bin:/usr/bin"
        "TZDIR=${pkgs.tzdata}/share/zoneinfo"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
        "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
        "NIX_REMOTE=daemon"
        "NIX_LD=${pkgs.stdenv.cc.bintools.dynamicLinker}"
        "NIX_LD_LIBRARY_PATH=${foreign.libraryPath}"
      ];
    };
}
