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

# ------

pushd $kern

# ------
echo "this script updates only the 0003-gpio-virt-kernel.patch, before rebuilding Ghaf"

# 0003-gpio-virt-kernel.patch    # exclude /drive/Kconfig and drive/Makefile
git -C kernel-5.10/ diff basepoint -- drivers/gpio/ \
	>${patchdir}/0003-gpio-virt-kernel.patch
git -C kernel-5.10/ diff basepoint -- drivers/pinctrl/ \
	>>${patchdir}/0003-gpio-virt-kernel.patch
git -C kernel-5.10/ diff basepoint -- include/ \
	>>${patchdir}/0003-gpio-virt-kernel.patch

# ------

# build ghaf
cd ${ghaf}
./build.sh

# ------

popd
