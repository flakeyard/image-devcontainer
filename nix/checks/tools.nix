# Every tool builds, and its license allows redistribution. The tools have the
# client of OpenSSH, not its server.
{
  perSystem =
    { config, pkgs, ... }:
    let
      serverFiles = [
        "bin/sshd"
        "libexec/sshd-session"
        "libexec/sshd-auth"
        "libexec/sftp-server"
        "etc/ssh/sshd_config"
      ];
    in
    {
      checks.tools = pkgs.buildEnv {
        name = "image-tools";
        paths = config.image.parts.tools;
        ignoreCollisions = true;
        postBuild = ''
          [[ -x $out/bin/ssh ]] || { echo "no ssh in the tools" >&2; exit 1; }
          for file in ${pkgs.lib.escapeShellArgs serverFiles}; do
            [[ ! -e $out/$file ]] || { echo "the SSH server file $file is in the tools" >&2; exit 1; }
          done
        '';
      };
    };
}
