{
  description = "A project for the smoke tests whose shell fails to evaluate.";

  outputs = _: {
    devShells.x86_64-linux.default = throw "the broken fixture shell";
    devShells.aarch64-linux.default = throw "the broken fixture shell";
  };
}
