# /etc/nix/nix.conf of the image (FY-0005). Only root is trusted; other
# caches and keys go to /etc/nix/local.conf.
{
  perSystem =
    { config, ... }:
    let
      inherit (config.image.parts) users;
    in
    {
      image.parts.nixConf = ''
        build-users-group = ${users.buildGroup}
        extra-experimental-features = nix-command flakes
        max-jobs = auto
        # Builds run as build users without isolation: a sandbox needs privileges a
        # dev container does not have and would fall back silently. CI builds with
        # the sandbox on.
        sandbox = false
        trusted-users = root
        substituters = https://cache.nixos.org/
        trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
        # Collect garbage when the container disk runs low.
        min-free = ${toString (2 * 1024 * 1024 * 1024)}
        max-free = ${toString (8 * 1024 * 1024 * 1024)}
        !include /etc/nix/local.conf
      '';
    };
}
