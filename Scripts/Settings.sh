#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
	#修改WIFI地区
	sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
	#修改WIFI加密
	sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#无WIFI配置标志
if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
	echo "WRT_WIFI=wifi-no" >> $GITHUB_ENV
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#取消nss相关feed
	echo "CONFIG_FEED_nss_packages=n" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
	#设置NSS版本
	echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	#其他调整
	echo "CONFIG_PACKAGE_kmod-usb-serial-qualcomm=y" >> ./.config

	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

#调整网口顺序
sed -i 's/ucidef_set_interface_lan "lan1 lan2 lan3 lan4"/ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "lan4"/g' target/linux/airoha/an7581/base-files/etc/board.d/02_network
sed -i 's/interrupts.*//g' target/linux/airoha/dts/an7581-nokia_xg-040g-md-common.dtsi


#==== 修复：禁用 XRAY_CORE_NAIVE ====
# cronet-go 的 musl/arm64 cgo 声明含 "-l:libcronet.a"，被 Go 的 #cgo LDFLAGS
# 安全校验拒绝（invalid flag in #cgo LDFLAGS），导致 xray-core 编译必然失败。
# 该选项在 x86_64 编译机上默认开启。禁用后 xray-core 仍正常编译，ssr-plus 可用，
# 仅失去 NaiveProxy 出站（cronet）能力，Naive 入站不受影响。
echo "# CONFIG_XRAY_CORE_NAIVE is not set" >> .config

#==== 追加：生成 XG-140G-TF 的 UBI 变体 ====
# 源码树里 TF 的 UBI 设备只有 nokia_xg-040g-tf-ubi。040G-TF 与 140G-TF 是同一套硬件
# （上游 nokia_xg-140g-tf 的 DEVICE_ALT0 即为 XG-040G-TF），这里按项目惯例补一份独立
# DTS 与设备定义，让产物文件名和 model 与 140G-TF 对上，硬件描述完全复用 TF 基类。
if [[ "${WRT_CONFIG}" == "AIROHA-ONU" ]] && [ -d target/linux/airoha ]; then
	if [ ! -f target/linux/airoha/dts/an7581-nokia_xg-140g-tf-ubi.dts ]; then
		cat > target/linux/airoha/dts/an7581-nokia_xg-140g-tf-ubi.dts <<'WRT_DTS'
// SPDX-License-Identifier: GPL-2.0-only OR MIT

#include "an7581-nokia_xg-040g-tf-common.dtsi"
#include "an758x-nokia_xg-040g-ubi-parts.dtsi"

/ {
	model = "Nokia Bell XG-140G-TF (UBI)";
	compatible = "nokia,xg-140g-tf-ubi", "airoha,an7581",
		     "airoha,en7581";
};
WRT_DTS
		echo "added dts an7581-nokia_xg-140g-tf-ubi.dts"
	fi

	# 让 02_network 把新设备的 compatible 识别为 TF 机型，否则会掉进
	# "*" 分支导致网口不初始化、DHCP 无法下发 IP。复用 040G-TF-ubi 的
	# 4 LAN + pon0 上行配置。
	NW="target/linux/airoha/an7581/base-files/etc/board.d/02_network"
	if [ -f "$NW" ] && ! grep -q "nokia,xg-140g-tf-ubi)" "$NW"; then
		sed -i 's/nokia,xg-040g-tf-ubi)/nokia,xg-040g-tf-ubi |\\\n\tnokia,xg-140g-tf-ubi)/' "$NW"
		echo "patched 02_network for nokia,xg-140g-tf-ubi"
	fi

	if ! grep -q "nokia_xg-140g-tf-ubi" target/linux/airoha/image/an7581.mk; then
		cat >> target/linux/airoha/image/an7581.mk <<'WRT_MK'

define Device/nokia_xg-140g-tf-ubi
  $(call Device/nokia_xg-040g-tf-common)
  DEVICE_MODEL := XG-140G-TF
  DEVICE_VARIANT := (UBI)
  DEVICE_DTS := an7581-nokia_xg-140g-tf-ubi
  UBOOTENV_IN_UBI := 1
  KERNEL_IN_UBI := 1
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 128k
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  IMAGES := sysupgrade.itb
  IMAGE/sysupgrade.itb := append-kernel | \
	fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | \
	append-metadata
  DEVICE_PACKAGES += fitblk
endef
TARGET_DEVICES += nokia_xg-140g-tf-ubi
WRT_MK
		echo "CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_nokia_xg-140g-tf-ubi=y" >> .config
		echo "added Device/nokia_xg-140g-tf-ubi"
	fi

	#==== 修复：补齐 LAN 口 DHCP 地址池（对齐 040G-MD）====
	# ponwrt 这套 base-files 的 config_generate 只生成 network，不生成 dhcp，
	# 预置的 /etc/config/dhcp 里 lan 段缺 start/limit/leasetime，导致 dnsmasq
	# 不生成 dhcp-range、无法下发 IP（必须手动设静态 IP 才能进管理页）。
	# 这里放一个 uci-defaults 脚本，首次开机在 config_generate 之后补齐这三项，
	# 与 040G-MD 官方固件一致（start=100 limit=150 leasetime=12h）。
	UDEF_DIR="package/base-files/files/etc/uci-defaults"
	mkdir -p "$UDEF_DIR"
	cat > "$UDEF_DIR/99-fix-dhcp-lan" <<'WRT_UCI'
#!/bin/sh
# 补齐 LAN DHCP 地址池（ponwrt base-files 默认缺失，对齐 040G-MD）
[ -f /etc/config/dhcp ] || exit 0
uci -q get dhcp.lan.start    >/dev/null || uci set dhcp.lan.start='100'
uci -q get dhcp.lan.limit    >/dev/null || uci set dhcp.lan.limit='150'
uci -q get dhcp.lan.leasetime >/dev/null || uci set dhcp.lan.leasetime='12h'
uci -q get dhcp.lan.dhcpv4   >/dev/null || uci set dhcp.lan.dhcpv4='server'
uci -q changes dhcp >/dev/null && uci commit dhcp
exit 0
WRT_UCI
		chmod +x "$UDEF_DIR/99-fix-dhcp-lan"
		echo "added uci-defaults 99-fix-dhcp-lan"
fi
