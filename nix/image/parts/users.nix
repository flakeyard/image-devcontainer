# Users and groups of the image: the developer `dev` and the build users of
# the Nix daemon.
{
  perSystem =
    { lib, ... }:
    let
      user = "dev";
      uid = 1000;
      home = "/home/${user}";
      # Relative to the image root, for the commands that build the image.
      homeRelative = lib.removePrefix "/" home;
      buildGroup = "nixbld";
      buildGid = 30000;
      buildUsers = map (n: "nixbld${toString n}") (lib.range 1 32);
      buildUserLines = lib.concatImapStrings (
        n: name:
        "${name}:x:${toString (buildGid + n)}:${toString buildGid}:Nix build user:/var/empty:/bin/false\n"
      ) buildUsers;
    in
    {
      image.parts.users = {
        inherit
          user
          uid
          home
          homeRelative
          buildGroup
          buildGid
          buildUsers
          ;

        passwd = ''
          root:x:0:0:root:/root:/bin/bash
          ${user}:x:${toString uid}:${toString uid}:${user}:${home}:/bin/bash
          ${buildUserLines}nobody:x:65534:65534:nobody:/var/empty:/bin/false
        '';

        group = ''
          root:x:0:
          ${user}:x:${toString uid}:
          ${buildGroup}:x:${toString buildGid}:${lib.concatStringsSep "," buildUsers}
          nogroup:x:65534:
        '';
      };
    };
}
