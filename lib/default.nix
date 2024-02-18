{ lib }:

let
  scopeLib = import ./scope.nix { inherit lib; };

  inherit (scopeLib) makeScope makeScopeWithSplicing';

  otherSplices = pkgs: f: {
    # `pkgs<host><target>` needs to be rescoped on top of `pkgs` for some reason.
    selfBuildBuild = makeScope (lib.makeScope pkgs.newScope (_self: pkgs.pkgsBuildBuild)).newScope f;
    selfBuildHost = makeScope (lib.makeScope pkgs.newScope (_self: pkgs.pkgsBuildHost)).newScope f;
    selfBuildTarget = makeScope (lib.makeScope pkgs.newScope (_self: pkgs.pkgsBuildTarget)).newScope f;
    selfHostHost = makeScope (lib.makeScope pkgs.newScope (_self: pkgs.pkgsHostHost)).newScope f;
    selfHostTarget = makeScope (lib.makeScope pkgs.newScope (_self: pkgs.pkgsHostTarget)).newScope f;
    selfTargetTarget = if pkgs.pkgsTargetTarget?newScope then makeScope (lib.makeScope pkgs.newScope (_self: pkgs.pkgsTargetTarget)).newScope f else { };
  };

  makePackageSet = pkgs: f:
    makeScopeWithSplicing'
      { inherit (pkgs) splicePackages newScope; }
      { inherit f; otherSplices = otherSplices pkgs f; };

  mergePackageSets = pkgsets:
    let
      pkgsMerged = lib.foldl' (acc: pkgset: acc // pkgset) { } pkgsets;
      f = (_self: pkgsMerged);
      # We don't care about which `newScope` we use here, because we override it in `f`.
      scope = lib.makeScope pkgsMerged.newScope f;
      # TODO: Use `__splicedPackages` to skip splicing twice.
    in
    makePackageSet scope f;
in
{
  inherit
    makePackageSet
    mergePackageSets;
}
