#!/bin/bash

if [ "$(id -u)" != "0" ]; then
    echo "错误: 此脚本需要 root 权限，请使用 sudo 运行。"
    exit 1
fi

for cmd in curl gzip grep sed; do
    if ! command -v $cmd &> /dev/null; then
        echo "错误: 缺少依赖命令 $cmd，请先安装该命令。"
        exit 1
    fi
done

echo "正在检测系统架构和 CPU 特性..."
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        if grep -q avx2 /proc/cpuinfo; then
            TARGET_ARCH="amd64"
            echo "  - 检测到 x86_64 架构，且支持 AVX2，使用高性能版 (amd64)"
        else
            TARGET_ARCH="amd64-compatible"
            echo "  - 检测到 x86_64 架构，但不支持 AVX2，使用兼容版 (amd64-compatible)"
        fi
        ;;
    aarch64 | arm64)
        TARGET_ARCH="arm64"
        echo "  - 检测到 ARM64 架构"
        ;;
    armv7l)
        TARGET_ARCH="armv7"
        echo "  - 检测到 ARMv7 架构"
        ;;
    *)
        echo "错误: 暂不支持的架构 $ARCH"
        exit 1
        ;;
esac

echo "正在获取 Mihomo 最新版本号..."
REPO="MetaCubeX/mihomo"
API_URL="https://api.github.com/repos/$REPO/releases/latest"

VERSION=$(curl -sL "$API_URL" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$VERSION" ]; then
    echo "错误: 获取最新版本号失败，可能是 GitHub API 限制或网络问题。"
    exit 1
fi
echo "  - 最新版本为: $VERSION"

FILENAME="mihomo-linux-${TARGET_ARCH}-${VERSION}.gz"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$VERSION/$FILENAME"
TMP_FILE="/tmp/$FILENAME"
BIN_FILE="/usr/local/bin/mihomo"

echo "正在下载最新版本..."
echo "  - 下载链接: $DOWNLOAD_URL"
curl -L -# -o "$TMP_FILE" "$DOWNLOAD_URL"

if [ $? -ne 0 ]; then
    echo "错误: 文件下载失败!"
    rm -f "$TMP_FILE"
    exit 1
fi

echo "正在解压并安装..."
SERVICE_RESTARTED=0
if systemctl list-units --full -all | grep -Fq "mihomo.service"; then
    if systemctl is-active --quiet mihomo; then
        echo "  - 检测到正在运行的 mihomo 服务，正在停止..."
        systemctl stop mihomo
        SERVICE_RESTARTED=1
    fi
fi

gzip -d -f "$TMP_FILE"
EXTRACTED_FILE="/tmp/mihomo-linux-${TARGET_ARCH}-${VERSION}"

chmod +x "$EXTRACTED_FILE"
mv "$EXTRACTED_FILE" "$BIN_FILE"

if [ "$SERVICE_RESTARTED" -eq 1 ]; then
    echo "5. 正在重启 mihomo 服务..."
    systemctl start mihomo
fi

echo "✅ 安装/更新完成! 当前版本信息如下:"
$BIN_FILE -v