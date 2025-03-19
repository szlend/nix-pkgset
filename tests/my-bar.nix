{
  runCommand,
  my-foo,
  pkgsetBuildBuild,
}:

runCommand "my-bar" { nativeBuildInputs = [ my-foo ]; } ''
  echo "Running native spliced package"
  my-foo

  echo "Running native non-spliced package"
  ${pkgsetBuildBuild.my-foo}/bin/my-foo

  echo "Installing foreign spliced package"
  mkdir -p $out/bin
  ln -s ${my-foo}/bin/my-foo $out/bin/my-bar
''
