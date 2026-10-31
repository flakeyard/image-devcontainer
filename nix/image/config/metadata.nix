# The dev container metadata of the image, as JSON: what the dev container
# tools apply to every container of it.
{
  perSystem =
    { config, lib, ... }:
    {
      options.image.config.metadata = lib.mkOption {
        type = lib.types.str;
        description = "The devcontainer.metadata label of the image.";
      };
      config.image.config.metadata = builtins.toJSON [
        {
          remoteUser = config.image.parts.users.user;
          overrideCommand = false;
          init = true;
          updateRemoteUserUID = true;
        }
      ];
    };
}
