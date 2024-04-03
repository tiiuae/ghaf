home="/home/$(id -un)"
# sw=${PWD}
sw="${home}/software"
tegra="${home}/software/Jetson/Linux_for_Tegra"
kern="${tegra}/sources/kernel"
ghaf="${sw}/ghaf"
#patchdir="${ghaf}/modules/hardware/nvidia-jetson-orin/virtualization/common/gpio-virt-common/patches"
patchdir="${ghaf}/modules/jetpack/nvidia-jetson-orin/virtualization/common/gpio-virt-common/patches/"


# create empty tree to git diff against
empty=$(git hash-object -t tree /dev/null)

# make diff for dts files
# don't patch dts -- we are using overlays
#. dtsi_patch.sh

# ------

pushd $kern

# ------

# create patch for merged  Kconfig and Makefile in gpio-virt
# merge gpio-virt/drivers and kernel-5.10/drivers Makefile and Kconfig file

cp gpio-virt/drivers/Kconfig /tmp/original_Kconfig
cp gpio-virt/drivers/Makefile /tmp/original_Makefile

# "cat" option leaves functions in gpio-virt #undeclared
#cat kernel-5.10/drivers/Kconfig gpio-virt/drivers/Kconfig >gpio-virt/drivers/tmp_Kconfig
grep -veendmenu kernel-5.10/drivers/Kconfig >gpio-virt/drivers/tmp_Kconfig
grep -veappend_menu gpio-virt/drivers/Kconfig >>gpio-virt/drivers/tmp_Kconfig
mv gpio-virt/drivers/tmp_Kconfig gpio-virt/drivers/Kconfig

cat kernel-5.10/drivers/Makefile gpio-virt/drivers/Makefile >gpio-virt/drivers/tmp_Makefile
mv gpio-virt/drivers/tmp_Makefile gpio-virt/drivers/Makefile

# Merged patch should be made against files in kernel-5-10
# dont use ${empty} -- instead diff against merged files
git -C kernel-5.10/ diff -- drivers/Makefile ../gpio-virt/drivers/Makefile >${ghaf}/raw_MK_drivers.patch
git -C kernel-5.10/ diff -- drivers/Kconfig ../gpio-virt/drivers/Kconfig >>${ghaf}/raw_MK_drivers.patch
sed -i -e's/..\/gpio-virt\///' ${ghaf}/raw_MK_drivers.patch

# restore Kconfig and Makefile used in merged patch
mv /tmp/original_Kconfig gpio-virt/drivers/Kconfig  
mv /tmp/original_Makefile gpio-virt/drivers/Makefile

# ------

# 0002-vfio_platform-reset-required-false.patch       # not needed because of kernel boot parameters

# ------

# 0003-gpio-virt-kernel.patch    # exclude /drive/Kconfig and drive/Makefile
git -C kernel-5.10/ diff basepoint -- drivers/gpio/ \
	>${patchdir}/0003-gpio-virt-kernel.patch
git -C kernel-5.10/ diff basepoint -- drivers/pinctrl/ \
	>>${patchdir}/0003-gpio-virt-kernel.patch
git -C kernel-5.10/ diff basepoint -- include/ \
	>>${patchdir}/0003-gpio-virt-kernel.patch

# ------

# 0004-gpio-virt-drivers.patch
# include merged Kconfig and Makefile by using raw_MK_drivers.patch (note '>>')
mv ${ghaf}/raw_MK_drivers.patch ${patchdir}/0004-gpio-virt-drivers.patch
git -C gpio-virt/ diff ${empty} -- "drivers/gpio*" \
	>>${patchdir}/0004-gpio-virt-drivers.patch

# ------

# 0005-gpio-overlay.patch       # included in raw-kernel.patch -- not needed because we do not use overlay
git -C kernel-5.10/ diff basepoint -- "kernel*overlays.txt" \
	>${patchdir}/0005-gpio-overlay.patch

# ------

# 0006-defconfig-kernel.patch   # included in raw-kernel.patch
git -C kernel-5.10/ diff basepoint -- "arch/arm64/configs/defconfig" \
	>${patchdir}/0006-defconfig-kernel.patch

# ------

cd ${ghaf}

# ------

# build ghaf
. ${ghaf}/build.sh
