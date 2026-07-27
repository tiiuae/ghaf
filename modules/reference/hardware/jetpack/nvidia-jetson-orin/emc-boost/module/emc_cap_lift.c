// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: GPL-2.0-only
/*
 * One-shot lift of the BPMP-internal EMC bandwidth-manager frequency cap.
 *
 * BPMP boots with its bwmgr EMC cap at the DRAM boot rate (2133 MHz on
 * AGX Orin) and re-evaluates the EMC clock against it every second, so the
 * memory bus never reaches the trained maximum (3199 MHz on AGX Orin, a
 * ~50% bandwidth loss). The stock sysfs path
 * (/sys/kernel/nvpmodel_clk_cap/emc) cannot raise the cap: its store
 * handler sends CAP_SET(clk_round_rate(S64_MAX)) and round_rate is itself
 * clamped by the current cap. Stock JetPack lifts the cap from the nvphs
 * service, which Ghaf does not run.
 *
 * This module sends the one CAP_SET the sysfs path cannot. Nothing else
 * is needed: with the cap lifted, the demand-driven EMC DVFS governor
 * ranges freely between its idle and maximum rates.
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <soc/tegra/bpmp.h>

static unsigned long cap_hz = 3199000000UL;
module_param(cap_hz, ulong, 0444);
MODULE_PARM_DESC(cap_hz, "EMC frequency cap to request from BPMP (Hz)");

/*
 * From NVIDIA's downstream bpmp-abi.h (nv-oot tree); declared locally
 * because the upstream kernel's copy lacks the bwmgr_int MRQ. The MRQ is
 * served by BPMP firmware, so it is kernel-version independent.
 */
#define MRQ_BWMGR_INT		83
#define CMD_BWMGR_INT_CAP_SET	3

struct bwmgr_int_cap_set_req {
	u32 cmd;
	u64 rate;
} __packed;

static int __init emc_cap_lift_init(void)
{
	struct bwmgr_int_cap_set_req req = {
		.cmd = CMD_BWMGR_INT_CAP_SET,
		.rate = cap_hz,
	};
	u64 resp = 0;
	struct tegra_bpmp_message msg = {
		.mrq = MRQ_BWMGR_INT,
		.tx = { .data = &req, .size = sizeof(req) },
		.rx = { .data = &resp, .size = sizeof(resp) },
	};
	struct device_node *np;
	struct platform_device *pdev;
	struct tegra_bpmp *bpmp;
	int ret;

	/*
	 * Same lookup tegra_bpmp_get() performs, without needing a bound
	 * device: the BPMP platform device's drvdata is the tegra_bpmp
	 * handle. The tegra186 compatible is carried by the tegra234 node
	 * as well.
	 */
	np = of_find_compatible_node(NULL, NULL, "nvidia,tegra186-bpmp");
	if (!np)
		return -ENODEV;
	pdev = of_find_device_by_node(np);
	of_node_put(np);
	if (!pdev)
		return -ENODEV;
	bpmp = platform_get_drvdata(pdev);
	if (!bpmp) {
		put_device(&pdev->dev);
		return -EPROBE_DEFER;
	}

	ret = tegra_bpmp_transfer(bpmp, &msg);
	put_device(&pdev->dev);
	if (ret) {
		pr_err("emc_cap_lift: transfer failed: %d\n", ret);
		return ret;
	}
	if (msg.rx.ret) {
		pr_err("emc_cap_lift: BPMP refused cap %lu Hz: %d\n",
		       cap_hz, msg.rx.ret);
		return -EINVAL;
	}
	pr_info("emc_cap_lift: EMC cap set to %lu Hz\n", cap_hz);
	return 0;
}
module_init(emc_cap_lift_init);

static void __exit emc_cap_lift_exit(void)
{
	/* Nothing to undo: the cap stays until the next BPMP reset. */
}
module_exit(emc_cap_lift_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("One-shot BPMP EMC bwmgr cap lift");
