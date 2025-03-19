{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:

    let
      lib = nixpkgs.lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
    in
    {
      lib = import ./. { inherit lib; };
      checks = forAllSystems (system: import ./tests { inherit inputs system; });
    };
}
