export MAKEOPTS="-j12"
flake='.#nvidia-jetson-orin-agx-debug'
echo "Do you want to build only or switch to a new nix flake? (b/t/s/x/e/n)"
if [ $# == '0' ]
  then read ans
  else ans=$1
fi
export MAKEOPTS="-j12"
case $ans in
  b|B)
    echo "Building a nix derivation..."
    nixos-rebuild --flake ${flake} build
    ;;
  t|T)
    echo "Testing a nix derivation..."
    sudo nixos-rebuild --flake ${flake} test
    ;;
  s|S)
    echo "Switchng a nix derivation..."
    sudo nixos-rebuild --flake ${flake} switch
    ;;
  x|X)
    echo "Building a nix derivation with trace..."
    nixos-rebuild --flake ${flake} build --show-trace
    ;;
  e|E)
    echo "Evaluating to eval_${flake}.tmp"
    nix derivation show --show-trace --recursive ${flake} > eval_${flake}.tmp 
    ;;
  n|N)
    echo "Exiting..."
    exit 1
    ;;
  *)
    echo "Invalid input. Exiting..."
    exit 1
    ;;
esac

