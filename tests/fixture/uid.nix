# Writes the uid the build ran as. The builder is the image's /bin/sh.
derivation {
  name = "uid";
  system = builtins.currentSystem;
  builder = "/bin/sh";
  args = [
    "-c"
    ''
      while read -r key value rest; do
        if [ "$key" = Uid: ]; then echo "$value" >"$out"; fi
      done </proc/self/status
    ''
  ];
}
