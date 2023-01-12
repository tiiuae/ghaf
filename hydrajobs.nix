{self}: {
  hydraJobs = {
    vm.x86_64-linux = self.packages.x86_64-linux.vm;
    nvidia-jetson-orin.aarch64-linux = self.packages.aarch64-linux.nvidia-jetson-orin;

    doc = {
      x86_64-linux = self.packages.x86_64-linux.doc;
      aarch64-linux = self.packages.aarch64-linux.doc;
    };
  };
}
