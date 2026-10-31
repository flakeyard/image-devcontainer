# /etc/bashrc of the image.
{
  perSystem =
    { lib, ... }:
    {
      options.image.filesystem.bashrc = lib.mkOption {
        type = lib.types.lines;
        description = "The text of /etc/bashrc.";
      };
      config.image.filesystem.bashrc = ''
        # The profile of dev, for dev only: dev controls it, so root never
        # searches it (FY-0005).
        if [ "$(id -u)" != 0 ]; then
          case ":$PATH:" in
            *":$HOME/.nix-profile/bin:"*) ;;
            *) PATH=$HOME/.nix-profile/bin:$PATH ;;
          esac
        fi
        # Interactive shells enter project shells through direnv.
        [ -n "$PS1" ] || return
        eval "$(direnv hook bash)"
        PS1='\u@devcontainer:\w\$ '
      '';
    };
}
