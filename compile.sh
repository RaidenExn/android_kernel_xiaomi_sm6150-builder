#!/bin/bash
##################################################
# Unofficial LineageOS Perf kernel Compile Script
# Based on the original compile script by vbajs
# Forked by Riaru Moda
##################################################

# Strict error handling
set -e          # Exit on error
set -u          # Exit on undefined variable
set -o pipefail # Exit on pipe failure

# Error handler
error_exit() {
  echo "" >&2
  echo "❌ ERROR: $1" >&2
  echo "Build failed at line $2" >&2
  exit 1
}

# Trap errors
trap 'error_exit "Unexpected error" $LINENO' ERR

# Help message
help_message() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --ksu                Enable KernelSU support"
  echo "  --no-ksu             Disable KernelSU support"
  echo "  --ln8000             Enable ln8k charging support"
  echo "  --no-ln8000          Disable ln8k charging support"
  echo "  --f2fs               Enable F2FS compression support"
  echo "  --no-f2fs            Disable F2FS compression support"
  echo "  --nethunter-full     Enable full Kali NetHunter patches (HID, USB serial, extra drivers)"
  echo "  --no-nethunter-full  Disable NetHunter patches"
  echo "  --kprofiles          Enable KProfiles support (CPU/GPU profile management)"
  echo "  --no-kprofiles       Disable KProfiles support"
  echo "  --help               Show this help message"
}

# Environment setup
setup_environment() {
  echo "Setting up build environment..."
  export ARCH=arm64
  export KBUILD_BUILD_USER=riaru
  export KBUILD_BUILD_HOST=ximiedits
  export GCC64_DIR=$PWD/gcc64
  export GCC32_DIR=$PWD/gcc32
  export KSU_SETUP_URI="https://github.com/KernelSU-Next/KernelSU-Next"
  export KSU_BRANCH="legacy"
}

# Toolchain setup
setup_toolchain() {
  echo "Setting up toolchains..."

  if [ ! -d "$PWD/clang" ]; then
    echo "Cloning Clang r584948 (latest)..."
    
    # Try multiple sources in order
    CLANG_DOWNLOADED=false
    
    # Method 1: Try crdroid GitLab (fastest if works)
    if ! $CLANG_DOWNLOADED; then
      echo "Trying source 1: crdroid GitLab..."
      if git clone https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r584948.git \
        --depth=1 -b 18.0 clang 2>/dev/null; then
        CLANG_DOWNLOADED=true
        echo "✅ Downloaded from crdroid GitLab"
      else
        echo "⚠️ crdroid GitLab failed, trying next source..."
        rm -rf clang
      fi
    fi
    
    # Method 2: Try GitHub mirror (reliable)
    if ! $CLANG_DOWNLOADED; then
      echo "Trying source 2: GitHub mirror..."
      if git clone https://github.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r584948.git \
        --depth=1 clang 2>/dev/null; then
        CLANG_DOWNLOADED=true
        echo "✅ Downloaded from GitHub mirror"  
      else
        echo "⚠️ GitHub mirror failed, trying next source..."
        rm -rf clang
      fi
    fi
    
    # Method 3: Fallback to older but stable r547379
    if ! $CLANG_DOWNLOADED; then
      echo "Trying source 3: Stable r547379 (fallback)..."
      if git clone https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git \
        --depth=1 -b 15.0 clang 2>/dev/null; then
        CLANG_DOWNLOADED=true
        echo "✅ Downloaded Clang r547379 (fallback version)"
      else
        echo "❌ All Clang sources failed!"
        exit 1
      fi
    fi
    
    # Verify Clang was downloaded correctly
    if [ ! -f "clang/bin/clang" ]; then
      echo "❌ Error: Clang binary not found after download!"
      ls -la clang/
      exit 1
    fi
    
    echo "✅ Clang toolchain ready"
  else
    echo "Local clang dir found, using it."
  fi

  if [ ! -d "$PWD/gcc32" ] && [ ! -d "$PWD/gcc64" ]; then
    echo "Downloading GCC..."
    ASSET_URLS=$(curl -s "https://api.github.com/repos/mvaisakh/gcc-build/releases/latest" | grep "browser_download_url" | cut -d '"' -f 4 | grep -E "eva-gcc-arm.*\.xz")
    for url in $ASSET_URLS; do
      wget -nv --content-disposition -L "$url"
    done

    for file in eva-gcc-arm*.xz; do
      # The files are actually just plain tarballs named as .xz
      if [[ "$file" == *arm64* ]]; then
        tar -xf "$file" && mv gcc-arm64 gcc64
      else
        tar -xf "$file" && mv gcc-arm gcc32
      fi
      rm -rf "$file"
    done
  else
    echo "Local gcc dirs found, using them."
  fi
}

# Update PATH
update_path() {
  echo "Updating PATH..."
  export PATH="$PWD/clang/bin/:$GCC64_DIR/bin/:$GCC32_DIR/bin/:/usr/bin:$PATH"
}

# General Patches
add_patches() {
  echo "Adding patches..."
  wget -L https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernel-builder/-/raw/main/patches/4.14/add-rtl88xxau-5.6.4.2-drivers.patch -O rtl88xxau.patch
  patch -p1 < rtl88xxau.patch
  wget -L https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernel-builder/-/raw/main/patches/4.14/add-wifi-injection-4.14.patch -O wifi-injection.patch
  patch -p1 < wifi-injection.patch
  sed -i 's/# CONFIG_PID_NS is not set/CONFIG_PID_NS=y/' arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_POSIX_MQUEUE=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_SYSVIPC=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_CGROUP_DEVICE=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_DEVTMPFS=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_IPC_NS=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_DEVTMPFS_MOUNT=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_EROFS_FS=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_FSCACHE=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_FSCACHE_STATS=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_FSCACHE_HISTOGRAM=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_SECURITY_SELINUX_DEVELOP=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_FS_ENCRYPTION=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_EXT4_ENCRYPTION=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  echo "CONFIG_EXT4_FS_ENCRYPTION=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  sed -i 's/KBUILD_CFLAGS\s\++= -O2/KBUILD_CFLAGS   += -O3/g' Makefile
  sed -i 's/LDFLAGS\s\++= -O2/LDFLAGS += -O3/g' Makefile
}

add_ln8k() {
  local arg="$1"
  if [[ "$arg" == "--ln8000" ]]; then
    echo "Adding ln8k patches..."
    wget -L "https://github.com/PixelOS-Devices-old/kernel_xiaomi_sm6150/commit/e64a07f8d8beea4d7470e9ad4ef1b712d15909b5.patch" -O ln8k1.patch
    wget -L "https://github.com/PixelOS-Devices-old/kernel_xiaomi_sm6150/commit/39af7bb35ee22c2e6accde8c413151eda6b985d8.patch" -O ln8k2.patch
    wget -L "https://github.com/PixelOS-Devices-old/kernel_xiaomi_sm6150/commit/53133f4d9620f27d3d8fe3e021165cc93036cfb7.patch" -O ln8k3.patch
    wget -L "https://github.com/PixelOS-Devices-old/kernel_xiaomi_sm6150/commit/b8a6b2aefce81a1f6f51b9a46113ace0624aebdd.patch" -O ln8k4.patch
    wget -L "https://github.com/PixelOS-Devices-old/kernel_xiaomi_sm6150/commit/9d0cf7fd14477f290d7eeb8cb0107f29816935c0.patch" -O ln8k5.patch
    wget -L "https://github.com/PixelOS-Devices-old/kernel_xiaomi_sm6150/commit/022c13d583a127e9cc5534c778ea6d250b4a0528.patch" -O ln8k6.patch
    wget -L "https://github.com/PixelOS-Devices-old/kernel_xiaomi_sm6150/commit/2024605203354093ed2ec8294b7b0342baaf9c9d.patch" -O ln8k7.patch
    wget -L "https://github.com/PixelOS-Devices-old/kernel_xiaomi_sm6150/commit/bc4d92b3b9a6fda3504ef887685ad271e8dfd08d.patch" -O ln8k8.patch
    wget -L "https://github.com/PixelOS-Devices-old/kernel_xiaomi_sm6150/commit/39c4206ac149ebde881ca5e7be6f6f6a79f00ec6.patch" -O ln8k9.patch
    wget -L "https://github.com/PixelOS-Devices-old/kernel_xiaomi_sm6150/commit/49afb7c867b8ce8e28faa9564a010a7a4daa1eab.patch" -O ln8k10.patch
    wget -L "https://github.com/PixelOS-Devices-old/kernel_xiaomi_sm6150/commit/2b427aaf5af9748356d06f4048ef1f9b29ebf354.patch" -O ln8k11.patch
    patch -p1 < ln8k1.patch
    patch -p1 < ln8k2.patch
    patch -p1 < ln8k3.patch
    patch -p1 < ln8k4.patch
    patch -p1 < ln8k5.patch
    patch -p1 < ln8k6.patch
    patch -p1 < ln8k7.patch
    patch -p1 < ln8k8.patch
    patch -p1 < ln8k9.patch
    patch -p1 < ln8k10.patch
    patch -p1 < ln8k11.patch
    echo "CONFIG_CHARGER_LN8000=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    elif [[ "$arg" == "--no-ln8000" ]]; then
    echo "ln8k setup skipped."
  fi
}

add_f2fs() {
  local arg="$1"
  if [[ "$arg" == "--f2fs" ]]; then
    echo "Adding f2fs compression patches..."
    wget -L https://github.com/tbyool/android_kernel_xiaomi_sm6150/commit/02baeab5aaf5319e5d68f2319516efed262533ea.patch -O f2fscompression.patch
    patch -p1 < f2fscompression.patch
    echo "CONFIG_F2FS_FS_COMPRESSION=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_F2FS_FS_LZ4=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  elif [[ "$arg" == "--no-f2fs" ]]; then
    echo "f2fs compression setup skipped."
  fi
}

add_dtbo() {
  echo "Adding dtbo compile support..."
  wget -L "https://github.com/xiaomi-sm6150/android_kernel_xiaomi_sm6150/commit/e517bc363a19951ead919025a560f843c2c03ad3.patch" -O dtbo1.patch
  wget -L "https://github.com/xiaomi-sm6150/android_kernel_xiaomi_sm6150/commit/a62a3b05d0f29aab9c4bf8d15fe786a8c8a32c98.patch" -O dtbo2.patch
  wget -L "https://github.com/xiaomi-sm6150/android_kernel_xiaomi_sm6150/commit/4b89948ec7d610f997dd1dab813897f11f403a06.patch" -O dtbo3.patch
  wget -L "https://github.com/xiaomi-sm6150/android_kernel_xiaomi_sm6150/commit/fade7df36b01f2b170c78c63eb8fe0d11c613c4a.patch" -O dtbo4.patch
  wget -L "https://github.com/xiaomi-sm6150/android_kernel_xiaomi_sm6150/commit/2628183db0d96be8dae38a21f2b09cb10978f423.patch" -O dtbo5.patch
  wget -L "https://github.com/xiaomi-sm6150/android_kernel_xiaomi_sm6150/commit/31f4577af3f8255ae503a5b30d8f68906edde85f.patch" -O dtbo6.patch
  patch -p1 < dtbo1.patch
  patch -p1 < dtbo2.patch
  patch -p1 < dtbo3.patch
  patch -p1 < dtbo4.patch
  patch -p1 < dtbo5.patch
  patch -p1 < dtbo6.patch
}

# KSU Setup
setup_ksu() {
  local arg="$1"
  if [[ "$arg" == "--ksu" ]]; then
    echo "Setting up KernelSU..."
    echo "CONFIG_KSU=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_KSU_LSM_SECURITY_HOOKS=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_KSU_MANUAL_HOOKS=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_KSU_SUSFS=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_KSU_SUSFS_SUS_PATH=n" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=n" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    
    # Download and apply KSU patch
    wget -L "https://github.com/ximi-mojito-test/mojito_krenol/commit/8e25004fdc74d9bf6d902d02e402620c17c692df.patch" -O ksu.patch
    patch -p1 < ksu.patch || echo "⚠️ KSU patch partially applied, continuing..."
    
    patch -p1 < ksumakefile.patch || echo "⚠️ KSU Makefile patch partially applied, continuing..."
    
    # Download and apply kernel patches (may fail on some kernel versions)
    wget -L "https://github.com/TheSillyOk/kernel_ls_patches/raw/refs/heads/master/kpatch_fix.patch" -O kpatch_fix.patch
    if patch -p1 --dry-run < kpatch_fix.patch > /dev/null 2>&1; then
      patch -p1 < kpatch_fix.patch
      echo "✅ kpatch_fix applied successfully"
    else
      echo "⚠️ kpatch_fix.patch not compatible with this kernel version, skipping..."
    fi
    
    # Download and apply susfs patch (may fail on some kernel versions)
    wget -L "https://github.com/TheSillyOk/kernel_ls_patches/raw/refs/heads/master/susfs-2.0.0.patch" -O susfs.patch
    if patch -p1 --dry-run < susfs.patch > /dev/null 2>&1; then
      patch -p1 < susfs.patch
      echo "✅ susfs-2.0.0 patch applied successfully"
    else
      echo "⚠️ susfs-2.0.0.patch not compatible with this kernel version, skipping..."
      echo "   KernelSU will work but susfs features may be limited"
    fi
    
    # Clone KernelSU
    git clone "$KSU_SETUP_URI" -b "$KSU_BRANCH" KernelSU
    cd drivers
    ln -sfv ../KernelSU/kernel kernelsu
    cd ..
    
    # Apply KernelSU susfs integration patch
    cd KernelSU
    wget -L "https://raw.githubusercontent.com/TheSillyOk/kernel_ls_patches/refs/heads/master/KSUN/KSUN-SUSFS-2.0.0.patch" -O ksun_susfs.patch
    if patch -p1 --dry-run < ksun_susfs.patch > /dev/null 2>&1; then
      patch -p1 < ksun_susfs.patch
      echo "✅ KSUN-SUSFS patch applied successfully"
    else
      echo "⚠️ KSUN-SUSFS patch not compatible, skipping..."
      echo "   Basic KernelSU will still work"
    fi
    cd ..
  elif [[ "$arg" == "--no-ksu" ]]; then
    echo "KernelSU setup skipped."
  fi
}

# KProfiles Support
add_kprofiles() {
  local arg="$1"
  if [[ "$arg" == "--kprofiles" ]]; then
    echo "Adding KProfiles support..."
    
    # Clone KProfiles kernel module
    if [ ! -d "drivers/misc/kprofiles" ]; then
      echo "Cloning KProfiles kernel module..."
      git clone https://github.com/beakthoven/Kprofiles.git drivers/misc/kprofiles --depth=1
    else
      echo "KProfiles directory already exists, skipping clone"
    fi
    
    # Modify drivers/misc/Kconfig
    echo "Modifying drivers/misc/Kconfig..."
    if ! grep -q "source \"drivers/misc/kprofiles/Kconfig\"" drivers/misc/Kconfig; then
      sed -i '/^endmenu/i source "drivers/misc/kprofiles/Kconfig"' drivers/misc/Kconfig
    fi
    
    # Modify drivers/misc/Makefile
    echo "Modifying drivers/misc/Makefile..."
    if ! grep -q "obj-.CONFIG_KPROFILES" drivers/misc/Makefile; then
      echo "obj-\$(CONFIG_KPROFILES) += kprofiles/"  >> drivers/misc/Makefile
    fi
    
    # Enable KProfiles in kernel config
    echo "CONFIG_KPROFILES=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    
    echo "✅ KProfiles support added successfully"
  elif [[ "$arg" == "--no-kprofiles" ]]; then
    echo "KProfiles support skipped."
  fi
}

# NetHunter Full Support
add_nethunter_full() {
  local arg="$1"
  if [[ "$arg" == "--nethunter-full" ]]; then
    echo "Adding full Kali NetHunter compatibility patches..."
    
    # HID Keyboard/Mouse gadget support
    echo "CONFIG_USB_CONFIGFS_F_HID=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_USB_GADGET=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_USB_CONFIGFS=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_USB_LIBCOMPOSITE=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    
    # USB Serial/RNDIS support
    echo "CONFIG_USB_CONFIGFS_SERIAL=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_USB_CONFIGFS_RNDIS=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_USB_CONFIGFS_ECM=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_USB_CONFIGFS_NCM=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_USB_CONFIGFS_EEM=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    
    # USB ACM and Serial support
    echo "CONFIG_USB_ACM=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_USB_SERIAL=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_USB_SERIAL_GENERIC=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_USB_SERIAL_OPTION=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_USB_WDM=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    
    # Filesystem support
    echo "CONFIG_OVERLAY_FS=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_SQUASHFS=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_SQUASHFS_XZ=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    
    # Bluetooth support
    echo "CONFIG_BT_HCIBTUSB=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_BT_RFCOMM=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    
    # Network filtering
    echo "CONFIG_NETFILTER_XT_TARGET_TCPMSS=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_IP_NF_TARGET_MASQUERADE=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    echo "CONFIG_IP6_NF_TARGET_MASQUERADE=y" >> arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
    
    echo "✅ NetHunter full patches applied successfully"
  elif [[ "$arg" == "--no-nethunter-full" ]]; then
    echo "NetHunter full patches skipped."
  fi
}

# Compile kernel
compile_kernel() {
  echo -e "
===========================================" 
  echo "Starting kernel compilation..."
  echo "===========================================
"
  
  # Enable ccache if available
  if command -v ccache &> /dev/null; then
    export USE_CCACHE=1
    export CCACHE_DIR=$PWD/../.ccache
    echo "✅ ccache enabled (cache dir: $CCACHE_DIR)"
    ccache --zero-stats
  else
    echo "ℹ️ ccache not available, proceeding without cache"
  fi
  
  sed -i 's/CONFIG_LOCALVERSION="-perf"/CONFIG_LOCALVERSION="-perf-neon"/' arch/arm64/configs/vendor/sdmsteppe-perf_defconfig
  git config user.email "riarucompile@riaru.com"
  git config user.name "riaru-compile"
  git config set advice.addEmbeddedRepo true
  git add .
  git commit -m "cleanup: applied patches before build"
  make O=out ARCH=arm64 vendor/sdmsteppe-perf_defconfig
  make O=out ARCH=arm64 vendor/sweet.config
  
  # Calculate optimal job count (cores * 1.5 for I/O overlap)
  JOBS=$(($(nproc --all) * 3 / 2))
  echo "Building with $JOBS parallel jobs..."
  
  # Use ccache with clang if available
  if command -v ccache &> /dev/null; then
    CCACHE_CLANG="ccache clang"
  else
    CCACHE_CLANG="clang"
  fi
  
  make -j$JOBS \
    O=out \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    LD=ld.lld \
    AR=llvm-ar \
    NM=llvm-nm \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    CC="$CCACHE_CLANG" \
    CROSS_COMPILE=$GCC64_DIR/bin/aarch64-elf- \
    CROSS_COMPILE_COMPAT=$GCC32_DIR/bin/arm-eabi-
  
  # Show ccache statistics
  if command -v ccache &> /dev/null; then
    echo "
===========================================" 
    echo "📊 ccache Statistics:"
    echo "===========================================" 
    ccache --show-stats
  fi
  
  echo "
===========================================" 
  echo "✅ Kernel compilation completed!"
  echo "===========================================
"
}

# Main function
main() {
  case "$1" in
    --help)
      help_message
      exit 0
      ;;
  esac
  setup_environment
  setup_toolchain
  update_path
  add_patches
  add_dtbo
  add_f2fs "$3"
  add_ln8k "$2"
  setup_ksu "$1"
  add_kprofiles "$5"        # Add KProfiles as 5th argument
  add_nethunter_full "$4"  # Add NetHunter as 4th argument
  compile_kernel
}

# Run the main function
main "$1" "$2" "$3" "$4" "$5"
