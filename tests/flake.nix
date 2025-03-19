{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-pkgset.url = "github:github.com/szlend/nix-pkgset";
    nix-pkgset.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-pkgset,
      ...
    }:

    let
      lib = nixpkgs.lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
    in
    {
      legacyPackages = forAllSystems (
        system:

        nix-pkgset.lib.makePackageSet "pkgset" nixpkgs.legacyPackages.${system}.newScope (self: {
          my-foo = self.callPackage ./my-foo.nix { };
          my-bar = self.callPackage ./my-bar.nix { };
        })
      );

      packages = forAllSystems (
        system:

        lib.filterAttrs (_: lib.isDerivation) self.legacyPackages.${system}
      );
    };
}
