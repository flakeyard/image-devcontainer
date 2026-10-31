# The entrypoint of the image, with the tools it runs.
{
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.image.parts) nix;
      runtimeInputs = [
        nix
      ]
      ++ (with pkgs; [
        coreutils
        findutils
        gawk
        gnused
        util-linuxMinimal
        tini
      ]);
    in
    {
      image.parts.entrypoint = pkgs.writeShellApplication {
        name = "entrypoint";
        inherit runtimeInputs;
        # The tools on the fixed PATH of root's Nix processes, not the PATH the
        # container passes.
        text = ''
          entrypoint_tools=${pkgs.lib.makeBinPath runtimeInputs}
        ''
        + builtins.readFile ../../entrypoint/entrypoint.sh;
      };
    };
}
