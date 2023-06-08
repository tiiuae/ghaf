{pkgs, ... } :
{
  environment.systemPackages = with pkgs; [ 
    bmon
    clang 
    cmake 
    gcc11 
    git 
    glibc.static 
    gnumake 
    #gopkgs.go 
    lsb-release 
    udev 
    vim
  ];
}
