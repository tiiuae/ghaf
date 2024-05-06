if [ $(whoami) == "root" ]; then
	echo "Please, do not run as root -- dir paths will fail"
	exit 1
fi

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
# preparatory steps

# create patch for merged  Kconfig and Makefile in gpio-virt
# merge gpio-virt/drivers and kernel-5.10/drivers Makefile and Kconfig file

# stash away original Kconfig and Makefie files
cp gpio-virt/drivers/Kconfig /tmp/original_Kconfig
cp gpio-virt/drivers/Makefile /tmp/original_Makefile

# "cat" option leaves functions in gpio-virt #undeclared
#cat kernel-5.10/drivers/Kconfig gpio-virt/drivers/Kconfig >gpio-virt/drivers/tmp_Kconfig
#
# Make concatenated Kconfig
grep -veendmenu kernel-5.10/drivers/Kconfig >gpio-virt/drivers/tmp_Kconfig
grep -veappend_menu gpio-virt/drivers/Kconfig >>gpio-virt/drivers/tmp_Kconfig
mv gpio-virt/drivers/tmp_Kconfig gpio-virt/drivers/Kconfig

# Make concatenated Makefile 
cat kernel-5.10/drivers/Makefile gpio-virt/drivers/Makefile >gpio-virt/drivers/tmp_Makefile
mv gpio-virt/drivers/tmp_Makefile gpio-virt/drivers/Makefile

# Merged patch should be made against files in kernel-5-10
# dont use ${empty} -- instead diff against merged files

# diff Makefile and Kconfig 
#git -C kernel-5.10/ diff -- drivers/Makefile ../gpio-virt/drivers/Makefile   >${ghaf}/raw_MK_drivers.patch
git -C kernel-5.10/ diff -- drivers/Kconfig ../gpio-virt/drivers/Kconfig    >>${ghaf}/raw_MK_drivers.patch
# remove path to gpio-virt
sed -i -e's/..\/gpio-virt\///' ${ghaf}/raw_MK_drivers.patch

# make hacked -u0 diff for Makefile and Kconfig
echo "diff --git a/drivers/Makefile b/drivers/Makefile"            >${ghaf}/raw_u0_MK_drivers.patch
diff -u0 kernel-5.10/drivers/Makefile gpio-virt/drivers/Makefile  >>${ghaf}/raw_u0_MK_drivers.patch
#echo "diff --git a/drivers/Kconfig b/drivers/Kconfig"             >>${ghaf}/raw_u0_MK_drivers.patch
#diff -u0 kernel-5.10/drivers/Kconfig gpio-virt/drivers/Kconfig    >>${ghaf}/raw_u0_MK_drivers.patch
sed -i -e's/kernel-5.10/a/;s/gpio-virt/b/'                         ${ghaf}/raw_u0_MK_drivers.patch

# restore stashed Kconfig and Makefile used in merged patch
mv /tmp/original_Kconfig gpio-virt/drivers/Kconfig  
mv /tmp/original_Makefile gpio-virt/drivers/Makefile

#end of preparatory steps
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

# do not make the 0004 patch because it needs to be made with diff context 0, not to clash with bpmp patch.
# The clash concerns only the first git diff
# diff  --git a/drivers/Makefile b/drivers/Makefile
# edit the output of 'diff -u0' in its place
# or directly edit the patchfie 

# 0004-gpio-virt-drivers.patch
# include merged Kconfig and Makefile by using raw_MK_drivers.patch and raw_u0_MK_drivers.patch (note '>' and '>>')
cat ${ghaf}/raw_MK_drivers.patch ${ghaf}/raw_u0_MK_drivers.patch     >${patchdir}/0004-gpio-virt-drivers.patch
git -C gpio-virt/ diff ${empty} -- "drivers/gpio*"                  >>${patchdir}/0004-gpio-virt-drivers.patch

rm ${ghaf}/raw_MK_drivers.patch ${ghaf}/raw_u0_MK_drivers.patch

# ------

# 0005-gpio-overlay.patch       # included in raw-kernel.patch -- not needed because we do not use overlay
git -C kernel-5.10/ diff basepoint -- "kernel*overlays.txt" \
	>${patchdir}/0005-gpio-overlay.patch

# ------

# 0006-defconfig-kernel.patch   # included in raw-kernel.patch
git -C kernel-5.10/ diff basepoint -- "arch/arm64/configs/defconfig" \
	>${patchdir}/0006-defconfig-kernel.patch

# ------

# build ghaf
cd ${ghaf}
./build.sh $@

# ------

popd
