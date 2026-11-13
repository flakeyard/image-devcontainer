# The entrypoint of the image, with the tools it runs.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      root,
      ...
    }:
    let
      inherit (config.image.parts) nix environ;
      runtimeInputs = [
        nix
        environ
      ]
      ++ (with pkgs; [
        coreutils
        findutils
        gawk
        gnused
        util-linuxMinimal
      ]);
      shebang = "#!${pkgs.runtimeShell}\n";
      # Root's bash runs in privileged mode (-p): it ignores BASH_ENV, the
      # functions exported in the environment, and SHELLOPTS, BASHOPTS, CDPATH
      # and GLOBIGNORE, which the container's environment could set to run
      # code as root before the first line of the script.
      privilegedShebang = "#!${pkgs.runtimeShell} -p\n";
      # writeShellApplication cannot pass a flag to bash, so its shebang is
      # replaced; the build fails if it no longer starts the script.
      privileged =
        old:
        assert lib.assertMsg (lib.hasPrefix shebang old.text)
          "the entrypoint does not start with ${shebang}";
        {
          text = privilegedShebang + lib.removePrefix shebang old.text;
        };
    in
    {
      image.parts.entrypoint =
        (pkgs.writeShellApplication {
          name = "entrypoint";
          inherit runtimeInputs;
          # The tools on the fixed PATH of root's Nix processes, not the PATH the
          # container passes.
          text = ''
            entrypoint_tools=${lib.makeBinPath runtimeInputs}
          ''
          + builtins.readFile (root + "/entrypoint/entrypoint.sh");
        }).overrideAttrs
          privileged;
    };
}
