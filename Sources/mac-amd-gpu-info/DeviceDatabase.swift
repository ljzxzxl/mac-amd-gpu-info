import Foundation

/// 系统读不到的芯片级规格，按 device-id 静态补充（GPU-Z 亦是内置数据库）。
struct GPUSpec {
    var chip: String
    var architecture: String
    var process: String
    var shaders: Int
    var tmus: Int
    var rops: Int
    var computeUnits: Int
    var busWidthBit: Int
    var vramType: String
    var ratedCoreMHz: Int
    var ratedMemMHz: Int
    var dieSizeMM2: Int
    var transistorsB: Double
}

enum DeviceDatabase {
    /// 未收录返回 nil，UI 侧回退为"未知"。
    static func spec(deviceID: UInt32) -> GPUSpec? {
        switch deviceID {
        case 0x67DF: // Polaris 20：RX 570 / 580 系列
            return GPUSpec(chip: "Polaris 20 XT", architecture: "GCN 4.0", process: "14 nm",
                           shaders: 2304, tmus: 144, rops: 32, computeUnits: 36, busWidthBit: 256,
                           vramType: "GDDR5", ratedCoreMHz: 1340, ratedMemMHz: 2000,
                           dieSizeMM2: 232, transistorsB: 5.7)
        case 0x67EF: // Polaris 21：RX 460 / 560
            return GPUSpec(chip: "Polaris 21", architecture: "GCN 4.0", process: "14 nm",
                           shaders: 1024, tmus: 64, rops: 16, computeUnits: 16, busWidthBit: 128,
                           vramType: "GDDR5", ratedCoreMHz: 1275, ratedMemMHz: 1750,
                           dieSizeMM2: 123, transistorsB: 3.0)
        case 0x699F: // Polaris 12：RX 550
            return GPUSpec(chip: "Polaris 12", architecture: "GCN 4.0", process: "14 nm",
                           shaders: 640, tmus: 40, rops: 16, computeUnits: 10, busWidthBit: 128,
                           vramType: "GDDR5", ratedCoreMHz: 1183, ratedMemMHz: 1750,
                           dieSizeMM2: 101, transistorsB: 2.2)
        case 0x687F: // Vega 10：RX Vega 56 / 64
            return GPUSpec(chip: "Vega 10", architecture: "GCN 5.0", process: "14 nm",
                           shaders: 4096, tmus: 256, rops: 64, computeUnits: 64, busWidthBit: 2048,
                           vramType: "HBM2", ratedCoreMHz: 1546, ratedMemMHz: 945,
                           dieSizeMM2: 495, transistorsB: 12.5)
        case 0x731F: // Navi 10：RX 5700 / 5700 XT
            return GPUSpec(chip: "Navi 10", architecture: "RDNA 1.0", process: "7 nm",
                           shaders: 2560, tmus: 160, rops: 64, computeUnits: 40, busWidthBit: 256,
                           vramType: "GDDR6", ratedCoreMHz: 1755, ratedMemMHz: 1750,
                           dieSizeMM2: 251, transistorsB: 10.3)
        default:
            return nil
        }
    }
}
