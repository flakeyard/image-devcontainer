# Store paths the image uses outside its contents, through links and
# settings. In the contents they are garbage collection roots of the image's
# store.
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.image.parts) entrypoint foreign;
    in
    {
      options.image.roots = lib.mkOption {
        type = lib.types.package;
        description = "A link to each store path the image uses outside its contents.";
      };
      config.image.roots = pkgs.linkFarm "image-roots" (
        map (path: {
          # The name only; `path` keeps the dependency.
          name = builtins.unsafeDiscardStringContext (baseNameOf path);
          inherit path;
        }) (lib.unique ([ entrypoint ] ++ foreign.paths))
      );
    };
}
