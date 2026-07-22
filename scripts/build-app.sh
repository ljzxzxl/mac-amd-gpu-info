#!/bin/bash
# 编译并组装 MacAMDGPUInfo.app（通用二进制 x86_64 + arm64），
# 用 swiftc 直接编译，兼容仅装 Command Line Tools 的机器。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="MacAMDGPUInfo"
EXEC="mac-amd-gpu-info"
APP="build/$APP_NAME.app"
DEPLOY="11.0"

echo "[build-app] 编译 $EXEC (通用二进制 x86_64 + arm64) ..."
rm -rf "$APP" build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

SLICES=()
for arch in x86_64 arm64; do
    echo "[build-app]   - 构建 $arch ..."
    swiftc -O -target "${arch}-apple-macos${DEPLOY}" \
        -o "build/obj/${EXEC}-${arch}" Sources/"$EXEC"/*.swift \
        -framework AppKit -framework IOKit -framework Metal
    SLICES+=("build/obj/${EXEC}-${arch}")
done

# 合并为通用二进制
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/$EXEC"
echo "[build-app] 架构: $(lipo -archs "$APP/Contents/MacOS/$EXEC")"

cp Resources/Info.plist "$APP/Contents/Info.plist"

# 生成应用图标：由 Resources/AppIcon.png (1024) 生成多尺寸 AppIcon.icns
if [ -f Resources/AppIcon.png ]; then
    echo "[build-app] 生成 AppIcon.icns ..."
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16     Resources/AppIcon.png --out "$ICONSET/icon_16x16.png"      >/dev/null
    sips -z 32 32     Resources/AppIcon.png --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     Resources/AppIcon.png --out "$ICONSET/icon_32x32.png"      >/dev/null
    sips -z 64 64     Resources/AppIcon.png --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   Resources/AppIcon.png --out "$ICONSET/icon_128x128.png"    >/dev/null
    sips -z 256 256   Resources/AppIcon.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   Resources/AppIcon.png --out "$ICONSET/icon_256x256.png"    >/dev/null
    sips -z 512 512   Resources/AppIcon.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   Resources/AppIcon.png --out "$ICONSET/icon_512x512.png"    >/dev/null
    cp Resources/AppIcon.png "$ICONSET/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    cp Resources/AppIcon.png "$APP/Contents/Resources/AppIcon.png"
fi

/usr/bin/codesign --force --sign - "$APP" >/dev/null 2>&1 || \
    echo "[build-app] 警告：ad-hoc 签名失败，App 仍可运行"

echo "[build-app] 已生成 $APP"
