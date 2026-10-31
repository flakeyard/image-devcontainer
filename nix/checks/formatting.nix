# Every Nix file is formatted as `nix fmt` formats it.
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      nixFiles = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.fileFilter (file: file.hasExt "nix") ../..;
      };
    in
    {
      checks.formatting =
        pkgs.runCommand "formatting"
          {
            nativeBuildInputs = [
              pkgs.nixfmt
              pkgs.diffutils
            ];
          }
          ''
            status=0
            for file in $(find ${nixFiles} -name '*.nix'); do
              if ! nixfmt --check "$file" 2>/dev/null; then
                diff -u "$file" <(nixfmt - <"$file") || true
                status=1
              fi
            done
            [[ $status == 0 ]] && touch $out
          '';
    };
}
