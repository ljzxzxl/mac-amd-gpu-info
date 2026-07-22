#!/bin/bash
# 编译并组装 MacAMDGPUInfo.app。用 swiftc 直接编译，兼容仅装 Command Line Tools 的机器。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="MacAMDGPUInfo"
EXEC="mac-amd-gpu-info"
APP="build/$APP_NAME.app"

echo "[build-app] 编译 $EXEC ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -o "$APP/Contents/MacOS/$EXEC" Sources/"$EXEC"/*.swift \
    -framework AppKit -framework IOKit -framework Metal

cp Resources/Info.plist "$APP/Contents/Info.plist"

/usr/bin/codesign --force --sign - "$APP" >/dev/null 2>&1 || \
    echo "[build-app] 警告：ad-hoc 签名失败，App 仍可运行"

echo "[build-app] 已生成 $APP"
