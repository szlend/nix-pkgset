{ lib }:

let
  scopeLib = import ./scope.nix { inherit lib; };

  inherit (scopeLib) makeScope makeScopeWithSplicing';

  otherSplices = pkgs: f: {
    selfBuildBuild = makePackageSet pkgs.pkgsBuildBuild f;
    selfBuildHost = makePackageSet pkgs.pkgsBuildHost f;
    selfBuildTarget = makePackageSet pkgs.pkgsBuildTarget f;
    selfHostHost = makePackageSet pkgs.pkgsHostHost f;
    selfHostTarget = makePackageSet pkgs.pkgsHostTarget f;
    selfTargetTarget = if pkgs.pkgsTargetTarget?newScope then makePackageSet pkgs.pkgsTargetTarget f else { };
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

  packageSetFromOverlay = pkgs: overlay:
    let
      attrs = lib.attrNames (overlay pkgs pkgs);
      applyOverlay = pkgs: lib.fix (lib.extends overlay (_self: pkgs));
    in
    # Using `callParentPackage` here to avoid infinite recursion.
    makePackageSet pkgs (self:
      lib.getAttrs attrs (self.callParentScopePackage ({ pkgsHostTarget }: applyOverlay pkgsHostTarget) { }));
in
{
  inherit
    makePackageSet
    mergePackageSets
    packageSetFromOverlay;
}
