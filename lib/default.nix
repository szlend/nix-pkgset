{ lib }:

let
  scopeLib = import ./scope.nix { inherit lib; };

  inherit (scopeLib) makeScope makeScopeWithSplicing';

  otherSplices = pkgs: f: {
    selfBuildBuild = makeScope pkgs.pkgsBuildBuild.newScope f;
    selfBuildHost = makeScope pkgs.pkgsBuildHost.newScope f;
    selfBuildTarget = makeScope pkgs.pkgsBuildTarget.newScope f;
    selfHostHost = makeScope pkgs.pkgsHostHost.newScope f;
    selfHostTarget = makeScope pkgs.pkgsHostTarget.newScope f;
    selfTargetTarget = if pkgs.pkgsTargetTarget?newScope then makeScope pkgs.pkgsTargetTarget.newScope f else pkgs.pkgsTargetTarget;
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
