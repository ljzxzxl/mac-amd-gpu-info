import Foundation
import IOKit
import Metal

/// 通过 IOKit 读取 AMD 独显的静态信息与实时传感器数据。只读、无需 root。
enum GPUReader {

    // MARK: - 静态信息

    static func readInfo() -> GPUInfo {
        var info = GPUInfo(modelName: "未检测到 AMD 独显（RadeonX4000 家族）")
        info.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        info.metalSupport = metalSupport()

        guard let props = pciDeviceProps() else { return info }

        info.modelName = propString(props["model"]) ?? "AMD GPU"
        info.driver = "AMDRadeonX4000 家族（系统内置）"
        info.deviceID = dataLE32(props["device-id"])
        info.vendorID = dataLE32(props["vendor-id"])
        info.revisionID = dataLE32(props["revision-id"])
        info.vramMB = props["VRAM,totalMB"] as? Int
        info.pcieLink = pcieString(props["IOPCIExpressLinkStatus"] as? Int)

        var vbiosMemoryType: String?
        if let bin = props["ATY,bin_image"] as? Data, !bin.isEmpty {
            info.vbiosBytes = bin
            let v = VBIOSDecoder.decode(bin)
            info.biosPartNumber = v.partNumber
            info.biosVersion = v.atomVersion
            info.biosDate = v.date
            info.biosBoard = v.board
            info.subsystemString = v.subsystem
            info.memoryVendor = v.memoryVendor
            info.brand = v.brand
            vbiosMemoryType = v.memoryType
        }

        if let did = info.deviceID, let spec = DeviceDatabase.spec(deviceID: did) {
            info.chip = spec.chip
            info.architecture = spec.architecture
            info.process = spec.process
            info.shaders = spec.shaders
            info.tmus = spec.tmus
            info.rops = spec.rops
            info.computeUnits = spec.computeUnits
            info.busWidthBit = spec.busWidthBit
            info.vramType = spec.vramType
            info.ratedCoreMHz = spec.ratedCoreMHz
            info.ratedMemMHz = spec.ratedMemMHz
            info.dieSizeMM2 = spec.dieSizeMM2
            info.transistorsB = spec.transistorsB
        }
        // 机型库未命中显存类型时，用 VBIOS 推断值兜底。
        if info.vramType == nil { info.vramType = vbiosMemoryType }
        return info
    }

    /// 匹配 IOPCIDevice，返回第一张 model 含 "Radeon" 的 GPU 的完整属性字典。
    private static func pciDeviceProps() -> [String: Any]? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault,
                                           IOServiceMatching("IOPCIDevice"), &it) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(it) }
        var service = IOIteratorNext(it)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let model = propString(dict["model"]), model.contains("Radeon") {
                IOObjectRelease(service)
                return dict
            }
            IOObjectRelease(service)
            service = IOIteratorNext(it)
        }
        return nil
    }

    // MARK: - 传感器

    static func readStats() -> GPUStats? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault,
                                           IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(it) }
        var service = IOIteratorNext(it)
        while service != 0 {
            if let cls = ioClassName(service), cls.contains("AMDRadeonX4000"),
               let perf = perfStats(service) {
                IOObjectRelease(service)
                return parseStats(perf)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(it)
        }
        return nil
    }

    private static func perfStats(_ service: io_object_t) -> [String: Any]? {
        guard let prop = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                         kCFAllocatorDefault, 0) else { return nil }
        return prop.takeRetainedValue() as? [String: Any]
    }

    private static func parseStats(_ perf: [String: Any]) -> GPUStats {
        func i(_ k: String) -> Int? {
            if let n = perf[k] as? NSNumber { return n.intValue }
            return nil
        }
        var s = GPUStats()
        s.fanRPM = i("Fan Speed(RPM)")
        s.fanPct = i("Fan Speed(%)")
        s.tempC = i("Temperature(C)")
        s.coreMHz = i("Core Clock(MHz)")
        s.memMHz = i("Memory Clock(MHz)")
        s.activityPct = i("GPU Activity(%)")
        s.deviceUtilPct = i("Device Utilization %")
        s.powerW = i("Total Power(W)")
        if let inUse = i("inUseVidMemoryBytes") { s.vramInUseMB = inUse / 1_048_576 }
        return s
    }

    // MARK: - 工具

    private static func ioClassName(_ service: io_object_t) -> String? {
        var name = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(service, &name) == KERN_SUCCESS else { return nil }
        return String(cString: name)
    }

    static func propString(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let d = v as? Data {
            return String(decoding: d, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func dataLE32(_ v: Any?) -> UInt32? {
        guard let d = v as? Data else { return nil }
        var val: UInt32 = 0
        for (i, b) in d.prefix(4).enumerated() { val |= UInt32(b) << (8 * i) }
        return val
    }

    private static func pcieString(_ status: Int?) -> String? {
        guard let s = status else { return nil }
        let speeds = ["?", "2.5 GT/s (Gen1)", "5.0 GT/s (Gen2)", "8.0 GT/s (Gen3)"]
        let sp = speeds[min(s & 0xF, 3)]
        let width = (s >> 4) & 0x3F
        return "PCIe ×\(width) @ \(sp)"
    }

    private static func metalSupport() -> String? {
        guard let dev = MTLCreateSystemDefaultDevice() else { return nil }
        if #available(macOS 13.0, *), dev.supportsFamily(.metal3) { return "Metal 3" }
        return "Metal（\(dev.name)）"
    }
}
