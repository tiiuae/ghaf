/**
 * Copyright 2025 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */
// @ts-check
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import starlightSidebarTopics from "starlight-sidebar-topics";
import starlightLinksValidator from "starlight-links-validator";

// https://astro.build/config
export default defineConfig({
  site: "https://ghaf.tii.ae",
  integrations: [
    starlight({
      title: "Ghaf Framework",
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/tiiuae/ghaf",
        },
      ],
      customCss: ["./src/styles/custom.css"],
      plugins: [
        starlightLinksValidator({
          errorOnInvalidHashes: false,
        }),
        starlightSidebarTopics(
          [
            {
              id: "ghaf-dev",
              label: "Ghaf Developer Reference",
              link: "/ghaf/overview/",
              icon: "open-book",
              items: [
                {
                  label: "Overview",
                  items: [
                    "ghaf/overview",
                    "ghaf/overview/features",
                    {
                      label: "Architecture",
                      items: [
                        "ghaf/overview/arch",
                        "ghaf/overview/arch/variants",
                        "ghaf/overview/arch/hardening",
                        "ghaf/overview/arch/secureboot",
                        "ghaf/overview/arch/stack",
                      ],
                    },
                    {
                      label: "Architecture Decision Records",
                      collapsed: true,
                      items: [
                        "ghaf/overview/arch/adr",
                        "ghaf/overview/arch/adr/minimal-host",
                        "ghaf/overview/arch/adr/netvm",
                        "ghaf/overview/arch/adr/idsvm",
                        "ghaf/overview/arch/adr/platform-bus-passthrough-support",
                      ],
                    },
                  ],
                },
                {
                  label: "Developer Guide",
                  items: [
                    {
                      label: "Reference",
                      items: [
                        "ghaf/dev/ref",
                        "ghaf/dev/ref/development",
                        "ghaf/dev/ref/build_and_run",
                        "ghaf/dev/ref/remote_build_setup",
                        "ghaf/dev/ref/installer",
                        "ghaf/dev/ref/cross_compilation",
                        "ghaf/dev/ref/creating_appvm",
                        "ghaf/dev/ref/hw-config",
                        "ghaf/dev/ref/profiles-config",
                        "ghaf/dev/ref/labwc",
                        "ghaf/dev/ref/cosmic",
                        "ghaf/dev/ref/idsvm-development",
                        "ghaf/dev/ref/systemd-service-config",
                      ],
                    },
                    {
                      label: "Troubleshooting",
                      items: [
                        "ghaf/dev/troubleshooting",
                        "ghaf/dev/troubleshooting/systemd/system-log",
                        "ghaf/dev/troubleshooting/systemd/systemctl",
                        "ghaf/dev/troubleshooting/systemd/systemd-analyzer",
                        "ghaf/dev/troubleshooting/systemd/strace",
                        "ghaf/dev/troubleshooting/systemd/early-shell",
                      ],
                    },
                    {
                      label: "Ghaf as a Library",
                      items: [
                        "ghaf/dev/library",
                        "ghaf/dev/library/example_project",
                        "ghaf/dev/library/modules_options",
                      ],
                    },
                    {
                      label: "Technologies",
                      items: [
                        "ghaf/dev/technologies",
                        "ghaf/dev/technologies/compartment",
                        {
                          label: "Passthrough",
                          items: [
                            "ghaf/dev/technologies/passthrough",
                            "ghaf/dev/technologies/vfio",
                            "ghaf/dev/technologies/device_tree_overlays_pt",
                            {
                              label: "NVIDIA Jetson AGX Orin",
                              collapsed: true,
                              items: [
                                "ghaf/dev/technologies/nvidia_agx_pt_uart",
                                "ghaf/dev/technologies/nvidia_agx_pt_pcie",
                                "ghaf/dev/technologies/nvidia_uarti_net_vm",
                                "ghaf/dev/technologies/nvidia_jetson_pt_gpu",
                              ],
                            },
                            {
                              label: "x86",
                              collapsed: true,
                              items: [
                                "ghaf/dev/technologies/x86_pcie_crosvm",
                                "ghaf/dev/technologies/x86_gpu_passthrough_qemu",
                              ],
                            },
                          ],
                        },
                        "ghaf/dev/technologies/nvidia_virtualization_bpmp",
                        "ghaf/dev/technologies/hypervisor_options",
                        "ghaf/dev/technologies/hardware_acceleration",
                      ],
                    },
                  ],
                },
                {
                  label: "Build System and Supply Chain",
                  items: [
                    "ghaf/scs/ci-cd-system",
                    {
                      label: "Supply Chain Security",
                      items: [
                        "ghaf/scs/scs",
                        "ghaf/scs/slsa-framework",
                        "ghaf/scs/sbom",
                        "ghaf/scs/pki",
                        "ghaf/scs/ghaf-security-fix-automation",
                        "ghaf/scs/patching-automation",
                      ],
                    },
                  ],
                },
                {
                  label: "Ghaf Showcases and Scenarios",
                  items: [
                    "ghaf/scenarios/showcases",
                    "ghaf/scenarios/run_win_vm",
                    "ghaf/scenarios/run_cuttlefish",
                  ],
                },
                {
                  label: "Release Notes",
                  collapsed: true,
                  autogenerate: { directory: "ghaf/releases" },
                },
                {
                  label: "Appendices",
                  collapsed: true,
                  items: [
                    "ghaf/appendices/glossary",
                    "ghaf/appendices/contributing_general",
                    {
                      label: "Research",
                      items: [
                        "ghaf/appendices/research/installation",
                        "ghaf/appendices/research/imx8qm-passthrough",
                      ],
                    },
                  ],
                },
              ],
            },
            {
              id: "givc",
              label: "Ghaf Inter-VM Communication",
              link: "/givc/overview/",
              icon: "seti:pipeline",
              items: [
                {
                  label: "Overview",
                  items: ["givc/overview", "givc/overview/arch"],
                },
                {
                  label: "Getting Started",
                  items: ["givc/examples", "givc/examples/modules"],
                },
                {
                  label: "API Reference",
                  items: [
                    "givc/api",
                    {
                      label: "NixOS Modules",
                      autogenerate: { directory: "givc/api/nixos" },
                    },
                    {
                      label: "GRPC API",
                      autogenerate: { directory: "givc/api/grpc" },
                    },
                    {
                      label: "Go API",
                      collapsed: true,
                      items: [
                        "givc/api/go/cmd/givc-agent",
                        {
                          label: "Go-GRPC API",
                          collapsed: true,
                          autogenerate: { directory: "givc/api/go/grpc" },
                        },
                        {
                          label: "Go Packages",
                          collapsed: true,
                          autogenerate: { directory: "givc/api/go/pkgs" },
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
          {
            exclude: [
              "/ghaf/overview/arch/adr/template",
              "/blog",
              "/blog/**/*",
            ],
          },
        ),
      ],
    }),
  ],
});
