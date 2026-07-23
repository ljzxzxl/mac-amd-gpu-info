import Foundation
import IOKit
import Metal

/// 通过 IOKit 读取 Intel 核显（iGPU）的静态信息与可得传感器。只读、无需 root。
/// macOS 对核显仅暴露负载与共享内存；温度/频率/功耗/风扇不可用（返回 nil，UI 降级为“—”）。
struct IntelGPUProvider: GPUProvider {

    private let intelVendorID: UInt32 = 0x8086

    // MARK: - 静态信息

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
               dataLE32(dict["vendor-id"]) == intelVendorID,
               hasIntelAccelerator(under: service) {
                var info = buildInfo(from: dict, service: service)
                var rid: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(service, &rid) == KERN_SUCCESS {
                    info.registryID = rid
                    info.metalSupport = metalSupport(registryID: rid) ?? info.metalSupport
                }
                info.pciLocation = dict["pcidebug"] as? String
                result.append(info)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(it)
        }
        return result
    }

    func readInfo() -> GPUInfo {
        readAllInfos().first ?? {
            var info = GPUInfo(modelName: "未检测到 Intel 核显")
            info.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            info.isIntegrated = true
            return info
        }()
    }

    private func buildInfo(from props: [String: Any], service: io_object_t) -> GPUInfo {
        var info = GPUInfo(modelName: propString(props["model"]) ?? "Intel 核显")
        info.isIntegrated = true
        info.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        info.metalSupport = metalSupport(registryID: nil)
        info.driver = "Intel 图形（系统内置）"
        info.deviceID = dataLE32(props["device-id"])
        info.vendorID = dataLE32(props["vendor-id"])
        info.revisionID = dataLE32(props["revision-id"])
        info.vramType = "共享（系统内存）"   // 核显无独立显存

        if let did = info.deviceID, let spec = DeviceDatabase.intelSpec(deviceID: did) {
            if propString(props["model"]) == nil { info.modelName = spec.name }
            info.chip = spec.name.replacingOccurrences(of: "Intel ", with: "")
            info.architecture = spec.architecture
            info.process = spec.process
            info.computeUnits = spec.executionUnits          // EU 数
            info.shaders = spec.executionUnits * 8           // 每 EU 8 个 ALU
            info.ratedCoreMHz = spec.maxMHz
        }
        return info
    }

    // MARK: - 传感器

    func readStats() -> GPUStats? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault,
                                           IOServiceMatching("IntelAccelerator"), &it) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(it) }
        let accel = IOIteratorNext(it)
        defer { if accel != 0 { IOObjectRelease(accel) } }
        guard accel != 0, let perf = perfStats(accel) else { return nil }
        return parseStats(perf)
    }

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

    /// 在子树中查找 IntelAccelerator 并读 PerformanceStatistics。
    private func acceleratorStats(under node: io_object_t) -> GPUStats? {
        if let cls = ioClassName(node), cls == "IntelAccelerator", let perf = perfStats(node) {
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

    /// iGPU 仅有负载与共享内存占用可用；温度/频率/功耗/风扇不可用。
    private func parseStats(_ perf: [String: Any]) -> GPUStats {
        func i(_ k: String) -> Int? {
            if let n = perf[k] as? NSNumber { return n.intValue }
            return nil
        }
        var s = GPUStats()
        let util = i("Device Utilization %")
        s.deviceUtilPct = util
        s.activityPct = util
        // gartUsedBytes 作为共享内存占用的可靠代理（inUseSysMemoryBytes 常为回绕的异常大值，不用）。
        if let gart = i("gartUsedBytes"), gart > 0 { s.vramInUseMB = gart / 1_048_576 }
        return s
    }

    // MARK: - 工具

    private func hasIntelAccelerator(under node: io_object_t) -> Bool {
        if let cls = ioClassName(node), cls == "IntelAccelerator" { return true }
        var child: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(node, kIOServicePlane, &child) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(child) }
        var c = IOIteratorNext(child)
        while c != 0 {
            if hasIntelAccelerator(under: c) { IOObjectRelease(c); return true }
            IOObjectRelease(c)
            c = IOIteratorNext(child)
        }
        return false
    }

    private func perfStats(_ service: io_object_t) -> [String: Any]? {
        guard let prop = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                         kCFAllocatorDefault, 0) else { return nil }
        return prop.takeRetainedValue() as? [String: Any]
    }

    private func ioClassName(_ service: io_object_t) -> String? {
        var name = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(service, &name) == KERN_SUCCESS else { return nil }
        return String(cString: name)
    }

    private func propString(_ v: Any?) -> String? {
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

    /// 用 MTLCopyAllDevices 按 registryID 匹配到对应 GPU 的 Metal 支持（比全局默认更准）。
    private func metalSupport(registryID: UInt64?) -> String? {
        let devices = MTLCopyAllDevices()
        let dev: MTLDevice?
        if let rid = registryID {
            dev = devices.first { $0.registryID == rid } ?? devices.first
        } else {
            dev = devices.first
        }
        guard let device = dev else { return nil }
        if #available(macOS 13.0, *), device.supportsFamily(.metal3) { return "Metal 3" }
        return "Metal (\(device.name))"
    }
}
