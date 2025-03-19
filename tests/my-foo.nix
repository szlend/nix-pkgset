{
  runCommand,
  hello,
  pkgsBuildBuild,
}:

runCommand "my-foo" { nativeBuildInputs = [ hello ]; } ''
  echo "Running native spliced package"
  hello

  echo "Running native non-spliced package"
  ${pkgsBuildBuild.hello}/bin/hello

  echo "Installing foreign spliced package"
  mkdir -p $out/bin
  ln -s ${hello}/bin/hello $out/bin/my-foo
''
