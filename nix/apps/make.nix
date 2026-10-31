# mkApp { name, script } SETTINGS: the app NAME, which runs SCRIPT with
# coreutils and the runtimeInputs of SETTINGS on PATH and the variables of
# their environment exported. Values are strings, such as store paths.
{
  perSystem =
    { lib, pkgs, ... }:
    {
      _module.args.mkApp =
        { name, script }:
        {
          description,
          runtimeInputs ? [ ],
          environment ? { },
        }:
        {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              inherit name;
              runtimeInputs = [ pkgs.coreutils ] ++ runtimeInputs;
              runtimeEnv = environment;
              text = builtins.readFile script;
            }
          );
          meta = { inherit description; };
        };
    };
}
