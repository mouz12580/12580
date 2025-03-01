#!/bin/bash
#set -e
#
# Copy this script inside the kernel directory
#

# Set linker and path variables
LINKER="lld"
DIR=$(readlink -f .)
MAIN=$(readlink -f "${DIR}/..")
export PATH="$MAIN/clang/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_COMPILER_STRING="$($MAIN/clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"

# Check for clang compiler; if missing, clone it from GitHub
if ! [ -d "$MAIN/clang" ]; then
    echo "No clang compiler found ... Cloning from GitHub"
    echo "Choose which Clang to use:"
    echo "1. ZyC Stable"
    echo "2. WeebX Stable"
    read -p "Enter the number of your choice: " clang_choice

    if [ "$clang_choice" = "1" ]; then
        wget "$(curl -s https://raw.githubusercontent.com/v3kt0r-87/Clang-Stable/main/clang-zyc.txt)" -O "zyc-clang.tar.gz"
        rm -rf clang && mkdir clang && tar -xvf zyc-clang.tar.gz -C clang && rm -rf zyc-clang.tar.gz
    elif [ "$clang_choice" = "2" ]; then
        wget "$(curl -s https://raw.githubusercontent.com/v3kt0r-87/Clang-Stable/main/clang-weebx.txt)" -O "weebx-clang.tar.gz"
        rm -rf clang && mkdir clang && tar -xvf weebx-clang.tar.gz -C clang && rm -rf weebx-clang.tar.gz
    else
        echo "Invalid choice. Exiting..."
        exit 1
    fi
fi

KERNEL_DIR=$(pwd)
ZIMAGE_DIR="$KERNEL_DIR/out/arch/arm64/boot"

# Speed up build process
MAKE="./makeparallel"
BUILD_START=$(date +"%s")
blue='\033[0;34m'
cyan='\033[0;36m'
yellow='\033[0;33m'
red='\033[0;31m'
nocol='\033[0m'

# Function to revert panel modifications (only if HyperOS modifications were applied)
revert_modifications() {
  if [ "$choice_rom" -eq 1 ]; then
    if [ "$choice_device" -eq 1 ]; then
      sed -i 's/qcom,mdss-pan-physical-width-dimension = <700>;$/qcom,mdss-pan-physical-width-dimension = <70>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
      sed -i 's/qcom,mdss-pan-physical-height-dimension = <1540>;$/qcom,mdss-pan-physical-height-dimension = <155>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
    elif [ "$choice_device" -eq 2 ]; then
      sed -i 's/qcom,mdss-pan-physical-width-dimension = <700>;$/qcom,mdss-pan-physical-width-dimension = <70>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
      sed -i 's/qcom,mdss-pan-physical-height-dimension = <1540>;$/qcom,mdss-pan-physical-height-dimension = <155>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
    fi
  fi
}

echo -e "$blue***********************************************"
echo "          BUILDING KERNEL          "
echo -e "***********************************************$nocol"

# Prompt for device choice
echo "Choose device:"
echo "1. Apollo"
echo "2. Alioth"
read -p "Enter choice (1/2): " choice_device

if [ "$choice_device" -eq 1 ]; then
  KERNEL_DEFCONFIG=apollo_defconfig
  DEVICE_NAME1="apollo"
  DEVICE_NAME2="apollon"
  IS_SLOT_DEVICE=0
  # Remove vendor_boot block for Apollo
  VENDOR_BOOT_LINES_REMOVED=1
else
  KERNEL_DEFCONFIG=alioth_defconfig
  DEVICE_NAME1="alioth"
  DEVICE_NAME2="aliothin"
  IS_SLOT_DEVICE=1
  VENDOR_BOOT_LINES_REMOVED=0
fi

# Prompt for ROM type
echo "Choose ROM type:"
echo -e "\e[33m1. Hyper Os\e[0m"
echo -e "\e[36m2. AOSP\e[0m"
read -p "Enter choice (1/2): " choice_rom

if [ "$choice_rom" -eq 1 ]; then
  type=HyperOs
  echo -e "\e[31mChanging panel dimensions for HyperOS...\e[0m"
  if [ "$choice_device" -eq 1 ]; then
    sed -i 's/qcom,mdss-pan-physical-width-dimension = <70>;$/qcom,mdss-pan-physical-width-dimension = <700>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
    sed -i 's/qcom,mdss-pan-physical-height-dimension = <155>;$/qcom,mdss-pan-physical-height-dimension = <1540>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
  elif [ "$choice_device" -eq 2 ]; then
    sed -i 's/qcom,mdss-pan-physical-width-dimension = <70>;$/qcom,mdss-pan-physical-width-dimension = <700>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
    sed -i 's/qcom,mdss-pan-physical-height-dimension = <155>;$/qcom,mdss-pan-physical-height-dimension = <1540>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
  fi
else
  echo -e "\e[32mNo modifications needed for AOSP.\e[0m"
  type=Aosp
fi

# Backup anykernel.sh
cp -p anykernel/anykernel.sh anykernel/anykernel.sh.bak

# Modify anykernel.sh based on device parameters
sed -i "s/device.name1=.*/device.name1=$DEVICE_NAME1/" anykernel/anykernel.sh
sed -i "s/device.name2=.*/device.name2=$DEVICE_NAME2/" anykernel/anykernel.sh
sed -i "s/is_slot_device=.*/is_slot_device=$IS_SLOT_DEVICE/" anykernel/anykernel.sh

# Remove vendor_boot block if necessary
if [ "$VENDOR_BOOT_LINES_REMOVED" -eq 1 ]; then
  sed -i '/## vendor_boot shell variables/,/## end vendor_boot install/d' anykernel/anykernel.sh
fi

# Kernel compilation
make $KERNEL_DEFCONFIG O=out CC=clang
make -j$(nproc --all) O=out \
  CC=clang \
  ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  NM=llvm-nm \
  OBJDUMP=llvm-objdump \
  STRIP=llvm-strip

TIME="$(date "+%Y%m%d-%H%M%S")"
mkdir -p tmp
cp -fp $ZIMAGE_DIR/Image.gz tmp
cp -fp $ZIMAGE_DIR/dtbo.img tmp
cp -fp $ZIMAGE_DIR/dtb tmp
cp -rp ./anykernel/* tmp
cd tmp
7za a -mx9 tmp.zip *
cd ..
rm *.zip
cp -fp tmp/tmp.zip RealKing-$DEVICE_NAME1-$type-$TIME.zip
rm -rf tmp
echo $TIME

# Restore anykernel.sh from backup
mv -f anykernel/anykernel.sh.bak anykernel/anykernel.sh

# Revert panel modifications if HyperOS was selected
if [ "$choice_rom" -eq 1 ]; then
  revert_modifications
fi
