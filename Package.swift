// swift-tools-version:5.7
import PackageDescription

// 单一可执行模块：数据采集与窗口 UI 同处一个 target，
// 既支持完整 Xcode 的 `swift build`，也支持仅 Command Line Tools 下用
// scripts/build-app.sh 里的 swiftc 直接编译。
let package = Package(
    name: "MacAMDGPUInfo",
    products: [
        .executable(name: "mac-amd-gpu-info", targets: ["mac-amd-gpu-info"]),
    ],
    targets: [
        .executableTarget(name: "mac-amd-gpu-info"),
    ]
)
