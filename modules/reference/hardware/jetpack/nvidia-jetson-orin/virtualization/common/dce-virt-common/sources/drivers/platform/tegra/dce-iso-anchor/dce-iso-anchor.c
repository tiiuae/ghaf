// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
/*
 * dce-iso-anchor: claim the nvdisplay ISO SMMU stream (smmu_iso StreamID 1)
 * with a translating domain and install the DCE high-IOVA -> carveout mappings
 * the display FE's scanout DMA needs under GPU passthrough.
 *
 * The guest hands the host-owned DCE R5 ctxdma FrameAddrs in the native
 * high-IOVA range (DCE_HI_BASE + carveout phys); the FE's ISO scanout fetch
 * issues those under SID 1 through smmu_iso (iommu@10000000). Host is headless,
 * display@13800000 unbound, nothing claims SID 1, and arm-smmu.disable_bypass=0
 * leaves the stream in BYPASS -- the high IOVA goes out as raw physical to
 * nowhere and the panel scans black. (Raw ISO addresses fail too: the R5 aborts
 * the whole UPDATE on a non-IOVA ctxdma address -- no completion, no raster.)
 *
 * Binding an anchor to <&smmu_iso 1> gives SID 1 a translating DMA domain;
 * mapping DCE_HI_BASE+carveout -> carveout makes the scanout fetch land on real
 * pixels. A prior attempt hung this off dce_host_proxy (dc382ce4) and broke its
 * IPC; the anchor is a separate DMA-less device so nothing else changes context.
 *
 * The DT node is created at runtime from an embedded overlay (flashed DTB has no
 * anchor node; live tree has __symbols__ so &smmu_iso resolves). Loadable any
 * time after boot, before gpu-vm starts.
 */

#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/iommu.h>
#include <linux/delay.h>

#include "dce-iso-anchor-dtbo.h"

/*
 * Canonical host-side definition of the display high-IOVA policy. The guest
 * emits DCE addresses as (carveout phys + DCE_HI_BASE) in nvdisplay patch 0006
 * (gpu-vm/patches/0006-dce-addresses-cpu-phys-high-iova.patch); the two live in
 * separate build domains (host module vs guest RM source) and cannot share a
 * header, so KEEP THE BASE AND RANGES IN SYNC with that patch -- a drift is a
 * silent DMA-isolation bug.
 */
#define DCE_HI_BASE 0x7f00000000ULL

static const struct { u64 pa; u64 size; } dce_hi_ranges[] = {
	{ 0x60000000, 0x04000000 },  /* vm_hs */
	{ 0x80000000, 0x30000000 },  /* vm_cma */
	{ 0xb0000000, 0x08000000 },  /* scanout */
};

static int ovcs_id;
static struct platform_device *anchor_pdev; /* only if we created it */
static struct platform_device *niso_anchor_pdev;

static int dce_iso_anchor_probe(struct platform_device *pdev)
{
	struct iommu_domain *dom = iommu_get_domain_for_dev(&pdev->dev);
	int i, ret;

	if (!dom) {
		dev_err(&pdev->dev, "no iommu domain (iommus missing?)\n");
		return -ENODEV;
	}
	dev_info(&pdev->dev, "iso domain type=%d\n", dom->type);

	for (i = 0; i < ARRAY_SIZE(dce_hi_ranges); i++) {
		u64 iova = DCE_HI_BASE + dce_hi_ranges[i].pa;

		if (iommu_iova_to_phys(dom, iova) == dce_hi_ranges[i].pa) {
			dev_info(&pdev->dev, "0x%llx already mapped\n", iova);
			continue;
		}
		ret = iommu_map(dom, iova, dce_hi_ranges[i].pa,
				dce_hi_ranges[i].size,
				IOMMU_READ | IOMMU_WRITE | IOMMU_CACHE,
				GFP_KERNEL);
		dev_info(&pdev->dev, "iso map 0x%llx -> 0x%llx sz 0x%llx = %d\n",
			 iova, dce_hi_ranges[i].pa, dce_hi_ranges[i].size, ret);
		if (ret)
			return ret;
	}

	return 0;
}

static const struct of_device_id dce_iso_anchor_of_match[] = {
	{ .compatible = "nvidia,dce-iso-anchor" },
	{ }
};
MODULE_DEVICE_TABLE(of, dce_iso_anchor_of_match);

static struct platform_driver dce_iso_anchor_driver = {
	.probe = dce_iso_anchor_probe,
	.driver = {
		.name = "dce-iso-anchor",
		.of_match_table = dce_iso_anchor_of_match,
	},
};

/* Create the platform device for an overlay-added root child unless OF_DYNAMIC's
 * bus notifier already did. Returns created pdev (NULL if one existed or
 * creation failed); drops the lookup reference either way. */
static struct platform_device *anchor_pdev_ensure(struct device_node *np)
{
	struct platform_device *existing = of_find_device_by_node(np);

	if (existing) {
		put_device(&existing->dev);
		return NULL;
	}
	return of_platform_device_create(np, NULL, NULL);
}

static int __init dce_iso_anchor_init(void)
{
	struct device_node *np;
	int ret;

	ret = of_overlay_fdt_apply(dce_iso_anchor_dtbo, dce_iso_anchor_dtbo_len,
				   &ovcs_id, NULL);
	if (ret) {
		pr_err("dce_iso_anchor: overlay apply failed: %d\n", ret);
		return ret;
	}

	np = of_find_node_by_path("/dce_iso_anchor");
	if (!np) {
		pr_err("dce_iso_anchor: node missing after overlay\n");
		of_overlay_remove(&ovcs_id);
		return -ENODEV;
	}
	anchor_pdev = anchor_pdev_ensure(np);
	of_node_put(np);

	/* Same for the NISO anchor (smmu_niso0 SID 7 = TEGRA234_SID_NVDISPLAY,
	 * the stock stream for display pushbuffer/instmem/notifier traffic). */
	np = of_find_node_by_path("/dce_niso_anchor");
	if (np) {
		niso_anchor_pdev = anchor_pdev_ensure(np);
		of_node_put(np);
	}

	ret = platform_driver_register(&dce_iso_anchor_driver);
	if (ret) {
		pr_err("dce_iso_anchor: driver register failed: %d\n", ret);
		if (niso_anchor_pdev)
			of_platform_device_destroy(&niso_anchor_pdev->dev, NULL);
		if (anchor_pdev)
			of_platform_device_destroy(&anchor_pdev->dev, NULL);
		of_overlay_remove(&ovcs_id);
	}

	return ret;
}
module_init(dce_iso_anchor_init);

/* No module_exit by design: must live for the boot. Binding the anchors makes
 * Tegra MC retag the NVDISPLAYR/NVDISPLAYR1 SID overrides (MC+0x490/+0x508)
 * from PASSTHROUGH 0x7f to the anchors' SMMU SIDs, and nothing restores them on
 * unbind -- unloading would tear down the translating domains while scanout
 * clients keep emitting into them (faults / white panel). No exit handler makes
 * rmmod impossible instead of unsafe. */

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("smmu_iso SID-1 anchor: DCE high-IOVA scanout mappings");
