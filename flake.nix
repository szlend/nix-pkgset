{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
    in
    {
      lib = import ./. { inherit lib; };

      legacyPackages = forAllSystems (system: {
        checks = nixpkgs.legacyPackages.${system}.linkFarm "checks"
          (lib.mapAttrsToList (name: path: { inherit name path; }) self.checks.${system});
      });

      checks = forAllSystems (system:
        import ./tests {
          pkgs = nixpkgs.legacyPackages.${system};
          nix-pkgset = self;
        }
      );
    };
}
