# shellcheck shell=bash
# Prints "missing TOOL" for each tool of the image that is not on PATH, then
# "done".
for tool in nix direnv bash ls find diff grep sed awk tar gzip xz bzip2 zstd less ps which mount getent curl git ssh tini; do
  command -v "$tool" >/dev/null || echo "missing $tool"
done
echo "done"
