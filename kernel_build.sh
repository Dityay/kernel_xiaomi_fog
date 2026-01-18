#!/bin/bash
export TZ='Europe/Kyiv'

# --- TELEGRAM CONFIGURATION ---
TOKEN="REPLACE_WITH_YOUR_BOT_TOKEN"
CHAT_ID="REPLACE_WITH_YOUR_CHAT_ID"
# ------------------------------

KERNNAME="バタースコッチ"
KERNVER=""
BUILDDATE=$(date +%Y%m%d)
LOG_FILE="build_log.txt"

GREEN='\033[0;32m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

# 1. Install Dependencies
echo -e "${PURPLE}Installing dependencies...${NC}"
sudo apt update && sudo apt install -y bc cpio flex zip binutils-aarch64-linux-gnu binutils-arm-linux-gnueabi

# Folders & Toolchain
CLANG_DIR="$(pwd)/clang-llvm"
KCONFIG="vendor/fog-perf_defconfig"

if [ ! -d "$CLANG_DIR" ]; then
    echo -e "${GREEN}Clang not found, cloning Azure Clang...${NC}"
    git clone --depth=1 -b main https://gitlab.com/Panchajanya1999/azure-clang "$CLANG_DIR"
fi

export KBUILD_BUILD_USER=rootd
export KBUILD_BUILD_HOST=cutiepatootie

# Build Function
make_fun() {
    make -j$(nproc --all) O=out ARCH=arm64 \
        CC="$CLANG_DIR/bin/clang" \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        LLVM_IAS=1 "$@"
}

# Initialize Log
echo "--- Build Started at $(date) ---" > "$LOG_FILE"

# Initial Telegram Message
curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
     -d chat_id="$CHAT_ID" \
     -d text="🚀 Kernel build for $KERNNAME started..."

# Prepare & Build
echo -e "${PURPLE}Setting up config...${NC}"
make_fun "$KCONFIG" >> "$LOG_FILE" 2>&1

echo -e "${PURPLE}Starting compilation...${NC}"
if make_fun 2>&1 | tee -a "$LOG_FILE"; then
    # If Success
    echo -e "${GREEN}Build successful!${NC}"
    
    # Packaging
    echo -e "${PURPLE}Cloning AnyKernel3 and packaging...${NC}"
    git clone --depth=1 https://github.com/Dityay/AnyKernel3 AnyKernel3
    
    cp out/arch/arm64/boot/Image.gz AnyKernel3/Image.gz
    cd AnyKernel3
    ZIP_NAME="$KERNNAME-$KERNVER-$BUILDDATE.zip"
    zip -r9 "$ZIP_NAME" . -x ".git*" -x "README.md" -x "*.zip"
    mv "$ZIP_NAME" ../
    cd ..

    # Send File & Success Log to Telegram
    CAPTION="✅ *Build Successful!* %0A📅 *Date:* $BUILDDATE %0A👤 *Built by:* $KBUILD_BUILD_USER %0A📱 *Device:* Fog"
    
    curl -F document=@"$ZIP_NAME" -F chat_id="$CHAT_ID" -F parse_mode="Markdown" -F caption="$CAPTION" "https://api.telegram.org/bot$TOKEN/sendDocument"
    curl -F document=@"$LOG_FILE" -F chat_id="$CHAT_ID" -F caption="📄 Build Log (Success)" "https://api.telegram.org/bot$TOKEN/sendDocument"
else
    # If Failed
    echo -e "${RED}Build failed! Check the log file.${NC}"
    ERROR_CAPTION="❌ *Build Failed!* %0A📅 *Date:* $BUILDDATE %0A📱 *Device:* Fog %0A%0ACheck the attached log for details."
    
    curl -F document=@"$LOG_FILE" -F chat_id="$CHAT_ID" -F parse_mode="Markdown" -F caption="$ERROR_CAPTION" "https://api.telegram.org/bot$TOKEN/sendDocument"
    exit 1
fi

# Cleanup
rm -rf AnyKernel3/
echo -e "${GREEN}Process completed!${NC}"
