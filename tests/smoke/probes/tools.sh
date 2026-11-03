# shellcheck shell=bash
# Prints "missing TOOL" for each tool of the image that is not on PATH,
# "ssh-server FILE" for each program or file of the SSH server outside the
# store, then "done".
for tool in nix direnv bash ls find diff grep sed awk tar gzip xz bzip2 zstd less ps which mount getent curl git ssh tini; do
  command -v "$tool" >/dev/null || echo "missing $tool"
done
command -v sshd >/dev/null && echo "ssh-server $(command -v sshd)"
for file in /bin/sshd /libexec/sshd-session /libexec/sshd-auth /libexec/sftp-server /etc/ssh/sshd_config; do
  [[ ! -e $file ]] || echo "ssh-server $file"
done
echo "done"
