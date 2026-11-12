# The process of the container: tini, which starts the entrypoint as root to
# run the Nix daemon; the entrypoint then switches to dev.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.image.parts)
        entrypoint
        environ
        tini
        users
        ;
    in
    {
      options.image.config.process = lib.mkOption {
        type = lib.types.raw;
        description = "The user, entrypoint, command and working directory of the image config.";
      };
      config.image.config.process = {
        User = "0:0";
        # tini handles signals from the start: a SIGTERM that reaches PID 1
        # before it has a handler is lost. -s: it reaps orphans also when it
        # is not PID 1, under the init of the engine (`init: true`). -g: it
        # forwards signals to the group of the command, as a terminal does.
        # environ starts the entrypoint with an empty environment and passes
        # that of the container through a descriptor, for the command of dev.
        Entrypoint = [
          (lib.getExe tini)
          "-s"
          "-g"
          "--"
          (lib.getExe environ)
          "to-fd"
          (lib.getExe entrypoint)
        ];
        Cmd = [
          "${pkgs.coreutils}/bin/sleep"
          "infinity"
        ];
        WorkingDir = users.home;
      };
    };
}
