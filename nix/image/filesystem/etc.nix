# Commands for the image root: the files of /etc.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.image) parts filesystem;
      inherit (parts) users;
    in
    {
      options.image.filesystem.etc = lib.mkOption {
        type = lib.types.lines;
        description = "Commands that write the files of /etc.";
      };
      config.image.filesystem.etc = ''
        # Regular files, not links into the store: tools edit them in place.
        rm -f etc/passwd etc/group etc/nix/nix.conf etc/profile.d/nix.sh etc/profile.d/nix-daemon.sh
        cp ${pkgs.writeText "passwd" users.passwd} etc/passwd
        cp ${pkgs.writeText "group" users.group} etc/group
        cp ${pkgs.writeText "nix.conf" parts.nixConf} etc/nix/nix.conf
        cp ${pkgs.writeText "bashrc" filesystem.bashrc} etc/bashrc
        chmod 644 etc/passwd etc/group etc/nix/nix.conf etc/bashrc
        # Login shells get the same setup.
        echo '[ -f /etc/bashrc ] && . /etc/bashrc' > etc/profile
        printf 'passwd: files\ngroup: files\nhosts: files dns\n' > etc/nsswitch.conf
        printf '%s\n' 'NAME="flakeyard devcontainer"' 'ID=flakeyard' 'ID_LIKE=nixos' \
          'PRETTY_NAME="flakeyard devcontainer"' > etc/os-release
        ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-certificates.crt
      '';
    };
}
