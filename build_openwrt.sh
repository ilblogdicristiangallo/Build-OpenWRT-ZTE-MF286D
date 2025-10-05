#!/bin/bash
set -Eeuo pipefail
trap 'echo "[X] Error at line $LINENO. Exiting."; exit 1' ERR

# CONFIGURATION
VERSION="24.10.3"
TARGET="ipq40xx"
SUBTARGET="generic"
PROFILE="zte_mf286d"

BASE_URL="https://downloads.openwrt.org"
ARCHIVE_NAME="openwrt-imagebuilder-${VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.zst"
ARCHIVE_URL="${BASE_URL}/releases/${VERSION}/targets/${TARGET}/${SUBTARGET}/${ARCHIVE_NAME}"

PACKAGES="kmod-usb-serial-option kmod-usb-serial kmod-usb-serial-wwan \
usb-modeswitch kmod-mii kmod-usb-net kmod-usb-wdm \
kmod-usb-net-qmi-wwan uqmi kmod-usb-net-cdc-mbim \
luci-proto-qmi modemmanager"

# Check required tools
for t in wget tar make unzstd sha256sum; do
  command -v "$t" >/dev/null || { echo "[!] Missing tool: $t. Install with: sudo apt install $t"; exit 1; }
done

echo "==> OpenWrt ${VERSION} | Target: ${TARGET}/${SUBTARGET} | Profile: ${PROFILE}"
echo "==> Downloading ImageBuilder from: $ARCHIVE_URL"

# Download ImageBuilder if not already present
if [[ -f "$ARCHIVE_NAME" && -s "$ARCHIVE_NAME" ]]; then
    echo "[✓] ImageBuilder file already present: $ARCHIVE_NAME"
else
    wget --show-progress "$ARCHIVE_URL" -O "$ARCHIVE_NAME"
fi

# Extract ImageBuilder
tar --use-compress-program=unzstd -xf "$ARCHIVE_NAME"

# Detect extracted folder
FOLDER_NAME=$(find . -maxdepth 1 -type d -name "openwrt-imagebuilder-${VERSION}-*${TARGET}*${SUBTARGET}*" | head -n1)
[[ -d "$FOLDER_NAME" ]] || { echo "[X] ImageBuilder folder not found."; exit 1; }
echo "[✓] Found folder: $FOLDER_NAME"

# Automatically retrieve kernel modules hash for version 24.10.3
KMOD_HASH=$(wget -qO- "${BASE_URL}/releases/${VERSION}/targets/${TARGET}/${SUBTARGET}/kmods/" \
  | grep -oE '6\.6\.[0-9]+-1-[a-f0-9]{32}' | head -n1)

if [[ -z "$KMOD_HASH" ]]; then
  echo "[X] Unable to retrieve kernel modules hash. Please verify the version exists."
  exit 1
fi
echo "[✓] Kernel modules hash for ImageBuilder: $KMOD_HASH"

# Overwrite repositories.conf (local files + kmods only)
REPO_CONF="$FOLDER_NAME/repositories.conf"
cat > "$REPO_CONF" <<EOF
src/gz openwrt_core https://downloads.openwrt.org/releases/${VERSION}/targets/${TARGET}/${SUBTARGET}/packages
src/gz openwrt_base https://downloads.openwrt.org/releases/${VERSION}/packages/arm_cortex-a7_neon-vfpv4/base
src/gz openwrt_kmods https://downloads.openwrt.org/releases/${VERSION}/targets/${TARGET}/${SUBTARGET}/kmods/${KMOD_HASH}
src/gz openwrt_luci https://downloads.openwrt.org/releases/${VERSION}/packages/arm_cortex-a7_neon-vfpv4/luci
src/gz openwrt_packages https://downloads.openwrt.org/releases/${VERSION}/packages/arm_cortex-a7_neon-vfpv4/packages
src/gz openwrt_routing https://downloads.openwrt.org/releases/${VERSION}/packages/arm_cortex-a7_neon-vfpv4/routing
src/gz openwrt_telephony https://downloads.openwrt.org/releases/${VERSION}/packages/arm_cortex-a7_neon-vfpv4/telephony
src imagebuilder file:packages
option check_signature
EOF

# Network configuration
mkdir -p "$FOLDER_NAME/files/etc/config"
cat > "$FOLDER_NAME/files/etc/config/network" << 'EOF'
config interface 'loopback'
    option device 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config globals 'globals'
    option ula_prefix 'fd00:abcd::/48'

config device
    option name 'br-lan'
    option type 'bridge'
    list ports 'lan2'
    list ports 'lan3'
    list ports 'lan4'

config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '192.168.1.1'
    option netmask '255.255.255.0'
    option ip6assign '60'

config interface 'wan'
    option device '/dev/cdc-wdm0'
    option proto 'qmi'
    option apn 'internet'
    option auth 'none'
    option pdptype 'ipv4'
    option auto '1'

config interface 'wan6'
    option device 'wan'
    option proto 'dhcpv6'
EOF

# Firewall configuration
cat > "$FOLDER_NAME/files/etc/config/firewall" << 'EOF'
config defaults
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'REJECT'
    option syn_flood '1'

config zone
    option name 'lan'
    option network 'lan'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'

config zone
    option name 'wan'
    option network 'wan wan6'
    option input 'REJECT'
    option output 'ACCEPT'
    option forward 'REJECT'
    option masq '1'
    option mtu_fix '1'

config forwarding
    option src 'lan'
    option dest 'wan'
EOF

# Wi-Fi disabled configuration
cat > "$FOLDER_NAME/files/etc/config/wireless" << 'EOF'
config wifi-device 'radio0'
    option type 'mac80211'
    option path 'platform/soc/a000000.wifi'
    option band '2g'
    option htmode 'HT20'
    option channel 'auto'
    option country 'IT'
    option disabled '1'

config wifi-iface 'default_radio0'
    option device 'radio0'
    option network 'lan'
    option mode 'ap'
    option ssid 'OpenWrt'
    option encryption 'none'

config wifi-device 'radio1'
    option type 'mac80211'
    option path 'platform/soc/a800000.wifi'
    option band '5g'
    option htmode 'VHT40'
    option channel 'auto'
    option country 'IT'
    option disabled '1'

config wifi-iface 'default_radio1'
    option device 'radio1'
    option network 'lan'
    option mode 'ap'
    option ssid 'OpenWrt'
    option encryption 'none'
EOF

# Build image
cd "$FOLDER_NAME"
echo "==> Building image for ${PROFILE}..."
make image PROFILE="$PROFILE" FILES=files/ PACKAGES="$PACKAGES"

# Image output
OUT_DIR="bin/targets/${TARGET}/${SUBTARGET}"
SYSUPGRADE=$(find "$OUT_DIR" -name '*sysupgrade*.bin' | head -n1)
[[ -f "$SYSUPGRADE" ]] || { echo "[X] sysupgrade.bin not found."; exit 1; }

# Copy to Desktop
DEST=~/Desktop/sysupgrade-${PROFILE}-$(date +%Y%m%d-%H%M).bin
cp -f "$SYSUPGRADE" "$DEST"
echo "[✓] sysupgrade.bin copied to Desktop: $DEST"
