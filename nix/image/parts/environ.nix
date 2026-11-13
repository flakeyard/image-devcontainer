# The program that moves the environment into the arguments and back
# (entrypoint/environ.c), so that the processes of root start without the
# variables of the container. Static, with musl: no dynamic loader runs before
# it and reads LD_PRELOAD and the like.
{
  perSystem =
    { pkgs, root, ... }:
    {
      image.parts.environ =
        pkgs.pkgsStatic.runCommandCC "environ"
          {
            src = root + "/entrypoint/environ.c";
            meta.mainProgram = "environ";
          }
          ''
            mkdir -p $out/bin
            $CC -std=c11 -O2 -Wall -Wextra -Werror -s -o $out/bin/environ $src
          '';
    };
}
