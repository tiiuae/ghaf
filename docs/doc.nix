{ runCommandNoCC
, mdbook
,
}:
runCommandNoCC "ghaf-doc"
{
  nativeBuildInputs = [ mdbook ];
} ''
  ${mdbook}/bin/mdbook build -d $out ${./.}
''
