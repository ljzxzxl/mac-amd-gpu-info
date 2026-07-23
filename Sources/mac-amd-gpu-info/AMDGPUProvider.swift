import Foundation
import IOKit
import Metal

/// 通过 IOKit 读取 AMD 独显的静态信息与实时传感器数据。只读、无需 root。
struct AMDGPUProvider: GPUProvider {

    // MARK: - 静态信息

    /// 枚举所有 Radeon 独显（多卡），每项带稳定 registryID 作唯一键。
    func readAllInfos() -> [GPUInfo] {
        var result: [GPUInfo] = []
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault,
                                           IOServiceMatching("IOPCIDevice"), &it) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(it) }
        var service = IOIteratorNext(it)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let model = propString(dict["model"]), model.contains("Radeon") {
                var info = buildInfo(from: dict)
                var rid: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(service, &rid) == KERN_SUCCESS { info.registryID = rid }
                info.pciLocation = dict["pcidebug"] as? String
                // 驱动家族按实际 accelerator 类名（X4000/X5000/X6000）展示。
                if let cls = acceleratorClassName(under: service) {
                    let family = cls.components(separatedBy: "_").first ?? cls
                    info.driver = "\(family) 家族（系统内置）"
                }
                result.append(info)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(it)
        }
        return result
    }

    /// 首张 Radeon 的静态信息（无卡时返回占位）。
    func readInfo() -> GPUInfo {
        readAllInfos().first ?? {
            var info = GPUInfo(modelName: "未检测到 AMD 独显")
            info.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            info.metalSupport = metalSupport()
            return info
        }()
    }

    /// 从单个 IOPCIDevice 属性字典构建 GPUInfo（含 VBIOS、机型库、显存兜底）。
    private func buildInfo(from props: [String: Any]) -> GPUInfo {
        var info = GPUInfo(modelName: "AMD GPU")
        info.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        info.metalSupport = metalSupport()

        info.modelName = propString(props["model"]) ?? "AMD GPU"
        info.driver = "AMD Radeon（系统内置）"
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
        // 品牌兜底：无 VBIOS（如 Navi）时，用 PCI 子系统厂商 ID 推断 AIB 品牌。
        if info.brand == nil, let ssv = subsystemVendorID(from: props) {
            info.brand = DeviceDatabase.aibBrand(subsystemVendorID: ssv)
        }
        return info
    }

    /// 从 `compatible` 属性解析 PCI 子系统厂商 ID（首个 `pciVVVV,DDDD` 令牌的 VVVV）。
    private func subsystemVendorID(from props: [String: Any]) -> UInt32? {
        guard let d = props["compatible"] as? Data else { return nil }
        let s = String(decoding: d, as: UTF8.self)
        for raw in s.split(whereSeparator: { $0 == "\u{0}" }) {
            let t = raw.lowercased()
            guard t.hasPrefix("pci"), let comma = t.firstIndex(of: ",") else { continue }
            let vHex = String(t[t.index(t.startIndex, offsetBy: 3)..<comma])
            if vHex.count == 4, let v = UInt32(vHex, radix: 16) { return v }
        }
        return nil
    }

    // MARK: - 传感器

    /// 无指定卡时的兜底：返回系统中第一张 AMD accelerator 的传感器读数。
    /// 正常路径请用 readStats(pciRegistryID:) 精确读取选中卡，避免多卡串号。
    func readStats() -> GPUStats? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault,
                                           IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(it) }
        var service = IOIteratorNext(it)
        while service != 0 {
            if let cls = ioClassName(service), isAMDAccelerator(cls),
               let perf = perfStats(service) {
                IOObjectRelease(service)
                return parseStats(perf)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(it)
        }
        return nil
    }

    /// AMD 显卡 accelerator 类名判定：覆盖 X4000(Polaris)/X5000(Vega)/X6000(Navi/RDNA) 各家族。
    private func isAMDAccelerator(_ cls: String) -> Bool {
        cls.contains("AMDRadeon") && cls.contains("Accelerator")
    }

    /// 读取指定 PCI 卡（按 registryID）的传感器：定位该 PCI 节点后向下遍历子树找到它自己的 accelerator。
    func readStats(pciRegistryID: UInt64) -> GPUStats? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault,
                                           IORegistryEntryIDMatching(pciRegistryID), &it) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(it) }
        let pci = IOIteratorNext(it)
        defer { if pci != 0 { IOObjectRelease(pci) } }
        guard pci != 0 else { return nil }
        return acceleratorStats(under: pci)
    }

    /// 在给定节点的子树（IOService 平面）中查找 AMD accelerator 并读 PerformanceStatistics。
    private func acceleratorStats(under node: io_object_t) -> GPUStats? {
        if let cls = ioClassName(node), isAMDAccelerator(cls), let perf = perfStats(node) {
            return parseStats(perf)
        }
        var child: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(node, kIOServicePlane, &child) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(child) }
        var c = IOIteratorNext(child)
        while c != 0 {
            if let s = acceleratorStats(under: c) { IOObjectRelease(c); return s }
            IOObjectRelease(c)
            c = IOIteratorNext(child)
        }
        return nil
    }

    /// 在给定 PCI 节点子树中查找 AMD accelerator 的类名（用于展示驱动家族，如 AMDRadeonX6000）。
    private func acceleratorClassName(under node: io_object_t) -> String? {
        if let cls = ioClassName(node), isAMDAccelerator(cls) { return cls }
        var child: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(node, kIOServicePlane, &child) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(child) }
        var c = IOIteratorNext(child)
        while c != 0 {
            if let s = acceleratorClassName(under: c) { IOObjectRelease(c); return s }
            IOObjectRelease(c)
            c = IOIteratorNext(child)
        }
        return nil
    }

    private func perfStats(_ service: io_object_t) -> [String: Any]? {
        guard let prop = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                         kCFAllocatorDefault, 0) else { return nil }
        return prop.takeRetainedValue() as? [String: Any]
    }

    private func parseStats(_ perf: [String: Any]) -> GPUStats {
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
        s.powerW = i("Total Power(W)").map { Double($0) }
        if let inUse = i("inUseVidMemoryBytes") { s.vramInUseMB = inUse / 1_048_576 }
        return s
    }

    // MARK: - 工具

    private func ioClassName(_ service: io_object_t) -> String? {
        var name = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(service, &name) == KERN_SUCCESS else { return nil }
        return String(cString: name)
    }

    func propString(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let d = v as? Data {
            return String(decoding: d, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func dataLE32(_ v: Any?) -> UInt32? {
        guard let d = v as? Data else { return nil }
        var val: UInt32 = 0
        for (i, b) in d.prefix(4).enumerated() { val |= UInt32(b) << (8 * i) }
        return val
    }

    private func pcieString(_ status: Int?) -> String? {
        guard let s = status else { return nil }
        let speeds = ["?", "2.5 GT/s (Gen1)", "5.0 GT/s (Gen2)", "8.0 GT/s (Gen3)"]
        let sp = speeds[min(s & 0xF, 3)]
        let width = (s >> 4) & 0x3F
        return "PCIe ×\(width) @ \(sp)"
    }

    private func metalSupport() -> String? {
        guard let dev = MTLCreateSystemDefaultDevice() else { return nil }
#if arch(arm64)
        if #available(macOS 15.0, *) {
            if dev.supportsFamily(MTLGPUFamily.apple9) { return "Metal 4" }
        }
#endif
        if #available(macOS 13.0, *) {
            if dev.supportsFamily(.metal3) { return "Metal 3" }
        }
        return "Metal (\(dev.name))"
    }
}
