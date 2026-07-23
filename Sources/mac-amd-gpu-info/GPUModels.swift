import Foundation

/// 显卡静态信息（开机后基本不变，读取一次即可）。
struct GPUInfo {
    var modelName: String
    var brand: String?
    var chip: String?
    var architecture: String?
    var process: String?

    var deviceID: UInt32?
    var vendorID: UInt32?
    var revisionID: UInt32?
    var pcieLink: String?

    // 多卡标识
    var registryID: UInt64?   // IOPCIDevice 稳定注册表 ID，作为每张卡唯一键
    var pciLocation: String?  // pcidebug，如 "1:0:0"，用于区分同型号卡

    var vramMB: Int?
    var vramType: String?
    var memoryVendor: String?
    var busWidthBit: Int?

    var shaders: Int?
    var tmus: Int?
    var rops: Int?
    var computeUnits: Int?
    var ratedCoreMHz: Int?
    var ratedMemMHz: Int?
    var dieSizeMM2: Int?
    var transistorsB: Double?

    // VBIOS
    var biosPartNumber: String?
    var biosVersion: String?
    var biosDate: String?
    var biosBoard: String?
    var subsystemString: String?
    var vbiosBytes: Data?

    // 软件环境
    var osVersion: String?
    var metalSupport: String?
    var driver: String?
    var isAppleSilicon: Bool = false
    var isIntegrated: Bool = false   // Intel 核显等集成显卡

    init(modelName: String) { self.modelName = modelName }
}

/// 传感器实时读数，字段为 nil 表示缺失。
struct GPUStats {
    var fanRPM: Int?
    var fanPct: Int?
    var tempC: Int?
    var coreMHz: Int?
    var memMHz: Int?
    var activityPct: Int?
    var deviceUtilPct: Int?
    var powerW: Double?
    var vramInUseMB: Int?
    var vramTotalMB: Int?
}
