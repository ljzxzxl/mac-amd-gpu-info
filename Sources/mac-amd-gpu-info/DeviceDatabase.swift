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

/// Intel 核显规格（无独立显存/位宽等概念，单独一张表）。
struct IntelGPUSpec {
    var name: String          // "Intel UHD Graphics 630"
    var architecture: String  // "Gen 9.5 GT2"
    var process: String       // "14 nm"
    var executionUnits: Int   // EU 数
    var baseMHz: Int
    var maxMHz: Int
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
        case 0x67FF: // Polaris 21：RX 550（P21 XT，本机 Sapphire 512 SP / 8 CU）
            return GPUSpec(chip: "Polaris 21", architecture: "GCN 4.0", process: "14 nm",
                           shaders: 512, tmus: 32, rops: 16, computeUnits: 8, busWidthBit: 128,
                           vramType: "GDDR5", ratedCoreMHz: 1183, ratedMemMHz: 1750,
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

    /// Intel 核显规格，按 device-id 查表（未收录返回 nil）。
    static func intelSpec(deviceID: UInt32) -> IntelGPUSpec? {
        switch deviceID {
        case 0x3E9B, 0x3E92, 0x3E98, 0x3E91:  // Coffee Lake UHD 630
            return IntelGPUSpec(name: "Intel UHD Graphics 630", architecture: "Gen 9.5 GT2", process: "14 nm",
                                executionUnits: 24, baseMHz: 350, maxMHz: 1200)
        case 0x5912, 0x591B, 0x5902:          // Kaby Lake HD 630
            return IntelGPUSpec(name: "Intel HD Graphics 630", architecture: "Gen 9.5 GT2", process: "14 nm",
                                executionUnits: 24, baseMHz: 350, maxMHz: 1150)
        case 0x1926, 0x1927, 0x1912, 0x191B:  // Skylake Iris/HD 5xx
            return IntelGPUSpec(name: "Intel Iris/HD Graphics 5xx", architecture: "Gen 9 GT2/GT3e", process: "14 nm",
                                executionUnits: 48, baseMHz: 300, maxMHz: 1050)
        case 0x0A2E, 0x0A26, 0x0D26:          // Haswell Iris 5100 / HD 5000
            return IntelGPUSpec(name: "Intel Iris/HD Graphics 5000", architecture: "Gen 7.5", process: "22 nm",
                                executionUnits: 40, baseMHz: 200, maxMHz: 1100)
        case 0x0412, 0x0416, 0x0D22:          // Haswell HD 4600 / Iris Pro
            return IntelGPUSpec(name: "Intel HD Graphics 4600", architecture: "Gen 7.5 GT2", process: "22 nm",
                                executionUnits: 20, baseMHz: 350, maxMHz: 1350)
        case 0x0166:                          // Ivy Bridge HD 4000
            return IntelGPUSpec(name: "Intel HD Graphics 4000", architecture: "Gen 7 GT2", process: "22 nm",
                                executionUnits: 16, baseMHz: 350, maxMHz: 1150)
        case 0x87CA, 0x591E:                  // UHD 617 / HD 615（低压）
            return IntelGPUSpec(name: "Intel UHD Graphics 617", architecture: "Gen 9.5 GT2", process: "14 nm",
                                executionUnits: 24, baseMHz: 300, maxMHz: 1050)
        default:
            return nil
        }
    }

    /// PCI 子系统厂商 ID → 板卡品牌（AIB 厂商）。用于无 VBIOS（如 Navi）时补全品牌。
    static func aibBrand(subsystemVendorID: UInt32) -> String? {        switch subsystemVendorID {
        case 0x1002: return "AMD"
        case 0x1043: return "ASUS"
        case 0x1458: return "GIGABYTE"
        case 0x1462: return "MSI"
        case 0x148C: return "PowerColor"
        case 0x1682: return "XFX"
        case 0x174B, 0x1DA2: return "Sapphire"
        case 0x1787: return "HIS"
        case 0x1849: return "ASRock"
        case 0x196E: return "PNY"
        case 0x19DA: return "Zotac"
        case 0x3842: return "EVGA"
        default: return nil
        }
    }
}
