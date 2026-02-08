/**
 * SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */
// @ts-check
import { defineConfig, passthroughImageService } from "astro/config";
import starlight from "@astrojs/starlight";
import starlightSidebarTopics from "starlight-sidebar-topics";
import starlightLinksValidator from "starlight-links-validator";

// https://astro.build/config
export default defineConfig({
  site: "https://ghaf.tii.ae",
  // Use passthrough image service to avoid Sharp dependency issues in Nix builds
  image: {
    service: passthroughImageService(),
  },
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
                        "ghaf/overview/arch/system-architecture",
                        "ghaf/overview/arch/inter-vm-communication-control",
                        "ghaf/overview/arch/variants",
                        "ghaf/overview/arch/hardening",
                        "ghaf/overview/arch/vm-memory-wipe",
                        "ghaf/overview/arch/prohibited-hardcoded-secrets",
                        "ghaf/overview/arch/critical-services-privilege-escalation",
                        "ghaf/overview/arch/system-logs-encryption",
                        "ghaf/overview/arch/vm-network-separation",
                        "ghaf/overview/arch/least-privilege",
                        "ghaf/overview/arch/separation-of-duties",
                        "ghaf/overview/arch/trusted-vm-whitelisted-repos",
                        "ghaf/overview/arch/secureboot",
                        "ghaf/overview/arch/stack",
                        "ghaf/overview/arch/guest-tpm",
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
                        "ghaf/overview/arch/adr/fss",
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
                        "ghaf/dev/ref/ubuntu-development-setup",
                        "ghaf/dev/ref/development",
                        "ghaf/dev/ref/build_and_run",
                        "ghaf/dev/ref/remote_build_setup",
                        "ghaf/dev/ref/installer",
                        "ghaf/dev/ref/cross_compilation",
                        "ghaf/dev/ref/deferred-disk-encryption",
                        "ghaf/dev/ref/creating_appvm",
                        "ghaf/dev/ref/hw-config",
                        "ghaf/dev/ref/profiles-config",
                        "ghaf/dev/ref/packages",
                        "ghaf/dev/ref/modules",
                        "ghaf/dev/ref/dependencies",
                        "ghaf/dev/ref/builder-functions",
                        "ghaf/dev/ref/cosmic",
                        "ghaf/dev/ref/idsvm-development",
                        "ghaf/dev/ref/systemd-service-config",
                        "ghaf/dev/ref/dynamic-hostname",
                        "ghaf/dev/ref/fleet",
                        "ghaf/dev/ref/memory-wipe",
                        "ghaf/dev/ref/kill_switch",
                        "ghaf/dev/ref/wireguard-gui",
                        "ghaf/dev/ref/yubikey",
                        "ghaf/dev/ref/ghaf-vms",
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
                        "ghaf/dev/global-config",
                        "ghaf/dev/library/example_project",
                        "ghaf/dev/library/modules_options",
                        {
                          label: "Library API",
                          collapsed: true,
                          items: [
                            "ghaf/dev/library/vm-helpers",
                            "ghaf/dev/library/features-api",
                            "ghaf/dev/library/profiles-api",
                          ],
                        },
                      ],
                    },
                    {
                      label: "Architecture",
                      collapsed: true,
                      items: [
                        "ghaf/dev/architecture",
                        "ghaf/dev/architecture/vm-composition",
                        "ghaf/dev/architecture/config-propagation",
                        "ghaf/dev/architecture/module-conventions",
                        "ghaf/dev/architecture/anti-patterns",
                      ],
                    },
                    {
                      label: "Developer Guides",
                      collapsed: true,
                      items: [
                        "ghaf/dev/guides",
                        "ghaf/dev/guides/writing-modules",
                        "ghaf/dev/guides/creating-vms",
                        "ghaf/dev/guides/adding-features",
                        "ghaf/dev/guides/extending-targets",
                        "ghaf/dev/guides/downstream-setup",
                        "ghaf/dev/guides/migration",
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
                        "ghaf/dev/technologies/fake-battery",
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
                        "ghaf/scs/fss",
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
