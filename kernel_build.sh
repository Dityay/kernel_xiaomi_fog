#!/bin/bash
export TZ='Europe/Kyiv'
set -o pipefail

# ===============================
# TELEGRAM CONFIG
# ===============================
#TOKEN="REPLACE_WITH_YOUR_BOT_TOKEN"
#CHAT_ID="REPLACE_WITH_YOUR_CHAT_ID"

TOKEN="${TG_TOKEN}"
CHAT_ID="${TG_CHAT}"

send_tg() {
  curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode "text=$1" >/dev/null
}

send_tg_file() {
  local FILE="$1"
  local CAPTION="$2"

  [[ ! -f "$FILE" ]] && return 0

  curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendDocument" \
    -F chat_id="$CHAT_ID" \
    -F document=@"$FILE" \
    -F caption="$CAPTION" >/dev/null
}

# ===============================
# BASIC INFO
# ===============================
KERNNAME="バタースコッチ"
KERNVER=$(git describe --tags --dirty 2>/dev/null || echo "r1")
BUILDDATE=$(date +%Y%m%d)
DEVICE="fog_rain_wind"
LOG_FILE="build_log.txt"
KCONFIG="vendor/fog-perf_defconfig"

# ===============================
# CHANGELOG (ENV BASED)
# ===============================
CHANGELOG_RAW="${KERNEL_CHANGELOG}"

if [[ -z "$CHANGELOG_RAW" ]]; then
  CHANGELOG_RAW="(no changelog provided)"
fi

# convert \n → real newline
CHANGELOG_REAL=$(printf "%b" "$CHANGELOG_RAW")

# ===============================
# COLORS
# ===============================
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

# ===============================
# DEPENDENCIES
# ===============================
echo -e "${PURPLE}Installing dependencies...${NC}"
sudo apt update || true
sudo apt install -y \
  bc cpio flex zip \
  binutils-aarch64-linux-gnu \
  binutils-arm-linux-gnueabi \
  build-essential \
  libssl-dev \
  libelf-dev \
  libncurses-dev \
  bison \
  dwarves

# ===============================
# TOOLCHAIN
# ===============================
CLANG_DIR="$(pwd)/clang-llvm"

if [[ ! -d "$CLANG_DIR" ]]; then
  echo -e "${GREEN}Clang not found, cloning Azure Clang...${NC}"
  git clone --depth=1 https://gitlab.com/Panchajanya1999/azure-clang "$CLANG_DIR"
fi

export PATH="$CLANG_DIR/bin:$PATH"

# ===============================
# BUILD ENV
# ===============================
export KBUILD_BUILD_USER="Butterscotch"
export KBUILD_BUILD_HOST="HometownLX"

# Pastikan LLVM digunakan sepenuhnya
export LLVM=1
export LLVM_IAS=1

make_fun() {
  make -j$(nproc) O=out ARCH=arm64 \
    CC=clang \
    LD=ld.lld \
    AR=llvm-ar \
    NM=llvm-nm \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    HOSTCC=gcc \
    HOSTCXX=g++ \
    HOSTLD=ld \
    HOSTLDFLAGS="-fuse-ld=lld" \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    LLVM=1 \
    LLVM_IAS=1 "$@"
}

# ===============================
# LOG INIT
# ===============================
echo "--- Build Started at $(date) ---" > "$LOG_FILE"
START_TIME=$(date +%s)

# ===============================
# TELEGRAM START
# ===============================
send_tg "🚀 Kernel build started
📦 Name: $KERNNAME
📱 Device: $DEVICE
🗓 Date: $BUILDDATE

📝 Changelog:
$CHANGELOG_REAL"

# ===============================
# BUILD
# ===============================
echo -e "${PURPLE}Setting up defconfig...${NC}"
make_fun "$KCONFIG" >> "$LOG_FILE" 2>&1

echo -e "${PURPLE}Compiling kernel...${NC}"
if make_fun 2>&1 | tee -a "$LOG_FILE"; then
  echo -e "${GREEN}Build success!${NC}"

  # ===============================
  # IMAGE DETECT
  # ===============================
  IMG=""
  for f in Image.gz Image Image.gz-dtb; do
    if [[ -f "out/arch/arm64/boot/$f" ]]; then
      IMG="out/arch/arm64/boot/$f"
      break
    fi
  done

  if [[ -z "$IMG" ]]; then
    echo "Kernel image not found!" | tee -a "$LOG_FILE"
    send_tg_file "$LOG_FILE" "❌ Image not found"
    exit 1
  fi

  # ===============================
  # PACKAGING
  # ===============================
  echo -e "${PURPLE}Packaging AnyKernel3...${NC}"
  git clone --depth=1 https://github.com/Dityay/AnyKernel3 AnyKernel3

  echo "$CHANGELOG_REAL" > changelog.txt

  cp "$IMG" AnyKernel3/
  cp changelog.txt AnyKernel3/

  cd AnyKernel3
  ZIP_NAME="${KERNNAME}-${KERNVER}-${BUILDDATE}.zip"
  zip -r9 "$ZIP_NAME" . -x ".git*" -x "README.md" -x "*.zip"
  mv "$ZIP_NAME" ../
  cd ..

  ls -lh "$ZIP_NAME"

  # ===============================
  # TELEGRAM SUCCESS
  # ===============================
  END_TIME=$(date +%s)
  BUILD_TIME=$((END_TIME - START_TIME))

  send_tg_file "$ZIP_NAME" "✅ Build Successful
Kernel: $KERNNAME
Version: $KERNVER
Device: $DEVICE
Time: ${BUILD_TIME}s

Changelog:
$CHANGELOG_REAL"

  send_tg_file "$LOG_FILE" "📄 Build Log (Success)"

else
  echo -e "${RED}Build failed!${NC}"
  send_tg_file "$LOG_FILE" "❌ Build Failed"
  exit 1
fi

# ===============================
# CLEANUP
# ===============================
rm -rf AnyKernel3 clang-llvm changelog.txt
echo -e "${GREEN}All done. Kernel cooked 🔥${NC}"

