# The OpenSSH client without the server (FY-0005): links to the client
# programs and the client configuration of OpenSSH, so that neither sshd nor
# its helpers and configuration are on PATH, in /libexec or in /etc/ssh. The
# server stays inside the store path of OpenSSH, which the client programs
# refer to; removing it there would mean building OpenSSH instead of
# substituting it.
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib openssh;
      programs = [
        "scp"
        "sftp"
        "ssh"
        "ssh-add"
        "ssh-agent"
        "ssh-copy-id"
        "ssh-keygen"
        "ssh-keyscan"
      ];
    in
    {
      image.parts.openssh-client =
        pkgs.runCommand "openssh-client" { meta = { inherit (openssh.meta) license; }; }
          ''
            mkdir -p $out/bin $out/etc/ssh
            for program in ${lib.escapeShellArgs programs}; do
              ln -s ${openssh}/bin/$program $out/bin/$program
            done
            ln -s ${openssh}/etc/ssh/ssh_config $out/etc/ssh/ssh_config
          '';
    };
}
