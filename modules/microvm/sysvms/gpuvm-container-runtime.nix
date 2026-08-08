# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.gpuContainerRuntime;
  partitionCfg = config.ghaf.virtualization.gpuPartitionManager;
  partitionManager = inputs.gpu-partition-manager.lib.mkManager {
    inherit pkgs;
    cudaHeaders = pkgs.nvidia-jetpack.cudaPackages.cuda_cudart;
    cudaDriver = pkgs.nvidia-jetpack.l4t-cuda;
  };
  partitionClient = pkgs.runCommand "gpu-partition-client" { } ''
    install -Dm755 ${partitionManager}/bin/gpu-partition-run \
      $out/bin/gpu-partition-run
  '';
  cudaClosureInfo = pkgs.closureInfo { rootPaths = [ pkgs.nvidia-jetpack.l4t-cuda ]; };
  cudaLibPath = lib.makeLibraryPath [ pkgs.nvidia-jetpack.l4t-cuda ];
  managedClosureInfo = pkgs.closureInfo { rootPaths = [ partitionClient ]; };
  jqArgs = [
    "--rawfile"
    "paths"
    "${cudaClosureInfo}/store-paths"
  ]
  ++ (
    if partitionCfg.enable then
      [
        "--rawfile"
        "managedPaths"
        "${managedClosureInfo}/store-paths"
        "--arg"
        "client"
        "${partitionClient}/bin/gpu-partition-run"
      ]
    else
      [
        "--arg"
        "managedPaths"
        ""
        "--arg"
        "client"
        ""
      ]
  )
  ++ [
    "--arg"
    "libPath"
    cudaLibPath
    "--arg"
    "managed"
    (lib.boolToString partitionCfg.enable)
  ];

  # The guest device layout is fixed by the passthrough DTS. Generate the CDI
  # specification at build time so gpu-vm does not need a mutable toolkit or a
  # privileged discovery helper at runtime.
  nvidiaCdiSpec =
    pkgs.runCommand "nvidia-cdi-spec" { nativeBuildInputs = [ pkgs.buildPackages.jq ]; }
      ''
        jq -n ${lib.escapeShellArgs jqArgs} \
          '{
            cdiVersion: "0.6.0",
            kind: "nvidia.com/gpu",
            devices: [
              {
                name: "all",
                containerEdits: {
                  # Hardware-enumerated set on JetPack r36. libcuda also needs
                  # the DRM render node and host1x fence for initialization.
                  deviceNodes: (
                    [
                      "/dev/nvhost-as-gpu",
                      "/dev/nvhost-ctrl-gpu",
                      "/dev/nvhost-ctxsw-gpu",
                      "/dev/nvhost-dbg-gpu",
                      "/dev/nvhost-gpu",
                      "/dev/nvhost-nvsched-gpu",
                      "/dev/nvhost-nvsched_ctrl_fifo-gpu",
                      "/dev/nvhost-power-gpu",
                      "/dev/nvhost-prof-ctx-gpu",
                      "/dev/nvhost-prof-dev-gpu",
                      "/dev/nvhost-prof-gpu",
                      "/dev/nvhost-sched-gpu",
                      "/dev/nvhost-tsg-gpu",
                      "/dev/nvmap",
                      "/dev/nvgpu/igpu0/as",
                      "/dev/nvgpu/igpu0/channel",
                      "/dev/nvgpu/igpu0/ctrl",
                      "/dev/nvgpu/igpu0/ctxsw",
                      "/dev/nvgpu/igpu0/dbg",
                      "/dev/nvgpu/igpu0/nvsched",
                      "/dev/nvgpu/igpu0/nvsched_ctrl_fifo",
                      "/dev/nvgpu/igpu0/power",
                      "/dev/nvgpu/igpu0/prof",
                      "/dev/nvgpu/igpu0/prof-ctx",
                      "/dev/nvgpu/igpu0/prof-dev",
                      "/dev/nvgpu/igpu0/sched",
                      "/dev/nvgpu/igpu0/tsg",
                      "/dev/dri/renderD128",
                      "/dev/host1x-fence"
                    ] | map({ path: . })
                  )
                }
              }
            ] + (if $managed == "true" then [
              {
                name: "managed",
                containerEdits: {
                  env: [ "GPU_PARTITION_SOCKET=/run/gpu-partition-manager/control.sock" ],
                  mounts: (
                    ((($managedPaths | split("\n") | map(select(length > 0)))
                      - ($paths | split("\n") | map(select(length > 0)))) | map({
                      hostPath: .,
                      containerPath: .,
                      options: [ "ro", "bind", "nosuid", "nodev" ]
                    })) + [
                      {
                        hostPath: $client,
                        containerPath: "/opt/ghaf/bin/gpu-partition-run",
                        options: [ "ro", "bind", "nosuid", "nodev" ]
                      },
                      {
                        hostPath: "/run/gpu-partition-manager/control.sock",
                        containerPath: "/run/gpu-partition-manager/control.sock",
                        options: [ "bind", "nosuid", "nodev" ]
                      }
                    ]
                  )
                }
              }
            ] else [] end),
            containerEdits: {
              env: [ ("LD_LIBRARY_PATH=" + $libPath) ],
              mounts: (
                $paths | split("\n") | map(select(length > 0) | {
                  hostPath: .,
                  containerPath: .,
                  options: [ "ro", "bind", "nosuid", "nodev" ]
                })
              )
            }
          }' > "$out"
      '';
in
{
  _file = ./gpuvm-container-runtime.nix;

  options.ghaf.virtualization.gpuContainerRuntime = {
    enable = lib.mkEnableOption "rootful Docker with NVIDIA CDI devices in gpu-vm";

    addGhafUserToDockerGroup = lib.mkEnableOption ''
      root-equivalent Docker access for the ghaf user in gpu-vm
    '';
  };

  config = lib.mkIf cfg.enable {
    ghaf.storagevm.directories = [
      {
        directory = "/var/lib/docker";
        mode = "0710";
      }
    ];

    ghaf.users.admin.addToDockerGroup = cfg.addGhafUserToDockerGroup;

    virtualisation.docker = {
      enable = true;
      daemon.settings = {
        features.cdi = true;
        cdi-spec-dirs = [ "/etc/cdi" ];
        no-new-privileges = true;
      };
    };

    environment.etc."cdi/nvidia.json".source = nvidiaCdiSpec;
  };
}
