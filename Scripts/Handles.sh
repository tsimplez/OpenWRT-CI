#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

FEEDS_PATH="./feeds"
PACKAGE_PATH="./package"

#################### ----- 自定义 start ---------- ####################

## daed 处理
echo "openwrt-daede package versions:"
for PKG_FILE in $PACKAGE_PATH/openwrt-daede/{dae,daed,luci-app-daede}/Makefile; do
	if [ ! -f "$PKG_FILE" ]; then
		echo "Missing package Makefile: $PKG_FILE"
		exit 1
	fi
	grep -H -E '^PKG_(VERSION|RELEASE):=' "$PKG_FILE"
done


# 新安装默认从 Lucky 官网下载最新 Beta 核心，并继续由插件自动匹配目标架构。
LUCKY_CONFIG="$PACKAGE_PATH/luci-app-lucky/luci-app-lucky/root/etc/config/lucky"
if [ ! -f "$LUCKY_CONFIG" ]; then
	echo "Missing Lucky config: $LUCKY_CONFIG"
	exit 1
fi

sed -i \
	-e "s/option mirror        'github'/option mirror        'r66666'/" \
	-e "s/option release_type  'stable'/option release_type  'beta'/" \
	"$LUCKY_CONFIG"

grep -q "option mirror        'r66666'" "$LUCKY_CONFIG" \
	&& grep -q "option release_type  'beta'" "$LUCKY_CONFIG" \
	|| { echo "Failed to configure Lucky Beta defaults"; exit 1; }

#################### ----- 自定义 end ---------- ####################

#修补命令统一入口：FIX <名称> <守卫目录> <命令...>
#守卫目录不存在时直接跳过，保证在 bash -e 下不中断
FIX() {
	local NAME=$1
	local GUARD=$2
	shift 2

	[ -d "$GUARD" ] || return 0

	echo " "
	if "$@"; then
		echo "$NAME has been fixed!"
	else
		echo "$NAME fix failed; continuing!"
	fi
}

#修改argon主题字体和颜色
FIX "theme-argon" "$PACKAGE_PATH/luci-theme-argon" sed -i \
	"s/primary '.*'/primary '#31a1a1'/g; s/'0.2'/'0.5'/g; s/'none'/'bing'/g; s/'600'/'normal'/g" \
	"$PACKAGE_PATH/luci-theme-argon/luci-app-argon-config/root/etc/config/argon"

#修改aurora菜单式样
FIX "theme-aurora" "$PACKAGE_PATH/luci-app-aurora-config" find \
	"$PACKAGE_PATH/luci-app-aurora-config/root/usr/share/aurora/" -type f -name '*.template' -exec sed -i \
	"s/nav_type '.*'/nav_type 'dropdown'/g; s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" {} +

#修改mini-diskmanager菜单位置
FIX "mini-diskmanager" "$PACKAGE_PATH/luci-app-mini-diskmanager" sed -i "s/services/system/g" \
	"$PACKAGE_PATH/luci-app-mini-diskmanager/luci-app-mini-diskmanager/root/usr/share/luci/menu.d/luci-app-mini-diskmanager.json"

#修改natmapt菜单位置
FIX "natmapt" "$PACKAGE_PATH/luci-app-natmapt" sed -i "s/network/services/g" \
	"$PACKAGE_PATH/luci-app-natmapt/root/usr/share/luci/menu.d/luci-app-natmap.json"

#修复Rust编译失败
FIX "rust" "$FEEDS_PATH/packages/lang/rust" sed -i 's/ci-llvm=true/ci-llvm=false/g' \
	"$FEEDS_PATH/packages/lang/rust/Makefile"
