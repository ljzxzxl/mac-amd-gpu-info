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
        guard IOServiceGetMatchingServices(kIOPortDefault,
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
        info.vramMB = acceleratorVRAM(under: service)   // 从 IntelAccelerator 的 VRAM,totalMB 取共享上限

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
        guard IOServiceGetMatchingServices(kIOPortDefault,
                                           IOServiceMatching("IntelAccelerator"), &it) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(it) }
        let accel = IOIteratorNext(it)
        defer { if accel != 0 { IOObjectRelease(accel) } }
        var s = GPUStats()
        if accel != 0, let perf = perfStats(accel) { s = parseStats(perf) }
        augment(&s)
        return s
    }

    /// accelerator 句柄进缓存，后续采集直接读属性；读失败（休眠恢复）时失效重建。
    func readStats(pciRegistryID: UInt64) -> GPUStats? {
        if let cached = AcceleratorCache.shared.service(for: pciRegistryID) {
            if let perf = perfStats(cached) {
                var s = parseStats(perf)
                augment(&s)
                return s
            }
            AcceleratorCache.shared.invalidate(pciRegistryID)
        }

        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOPortDefault,
                                           IORegistryEntryIDMatching(pciRegistryID), &it) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(it) }
        let pci = IOIteratorNext(it)
        defer { if pci != 0 { IOObjectRelease(pci) } }
        guard pci != 0, let accel = findAccelerator(under: pci), let perf = perfStats(accel) else { return nil }
        AcceleratorCache.shared.store(accel, for: pciRegistryID)
        var s = parseStats(perf)
        augment(&s)
        return s
    }

    /// 核显没有独立的温度/频率/功耗/风扇传感器，用 CPU/内存侧数据补齐：
    /// - 温度/风扇/功耗：SMC（CPU 温度、CPU 风扇、CPU 封装功耗，免 root）
    /// - 核心频率：CPU 标称频率（sysctl，A 方案）
    /// - 显存频率：系统内存速度（后台探测一次并缓存）
    private func augment(_ s: inout GPUStats) {
        if s.tempC == nil { s.tempC = SMCClient.cpuTemperature() }
        if s.fanRPM == nil { s.fanRPM = SMCClient.cpuFanRPM() }
        if s.powerW == nil { s.powerW = SMCClient.cpuPowerW() }
        if s.coreMHz == nil { s.coreMHz = Self.nominalCPUMHz }
        Self.ensureRAMProbe()
        if s.memMHz == nil { s.memMHz = Self.ramSpeedMHz }
        // 已授权则用 powermetrics 的 CPU 实时频率覆盖标称值（A→C 升级）
        PowermetricsHelper.shared.fillStats(&s)
    }

    /// CPU 标称频率（MHz），sysctl 取一次。
    static let nominalCPUMHz: Int? = {
        var f: UInt64 = 0
        var sz = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.cpufrequency", &f, &sz, nil, 0) == 0, f > 0 { return Int(f / 1_000_000) }
        return nil
    }()

    // 内存速度：system_profiler 较慢，后台探测一次并缓存，避免阻塞刷新。
    private static var ramSpeedMHz: Int?
    private static var ramProbed = false
    private static func ensureRAMProbe() {
        if ramProbed { return }
        ramProbed = true
        DispatchQueue.global(qos: .utility).async {
            let v = probeRAMSpeed()
            DispatchQueue.main.async { ramSpeedMHz = v }
        }
    }
    private static func probeRAMSpeed() -> Int? {
        let p = Process()
        p.launchPath = "/usr/sbin/system_profiler"
        p.arguments = ["SPMemoryDataType"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8),
              let r = out.range(of: #"[0-9]{3,5}\s*MHz"#, options: .regularExpression) else { return nil }
        return Int(out[r].filter { $0.isNumber })
    }

    /// 在子树中查找 IntelAccelerator。返回值已 retain，由调用方接管。
    private func findAccelerator(under node: io_object_t) -> io_object_t? {
        if let cls = ioClassName(node), cls == "IntelAccelerator", perfStats(node) != nil {
            IOObjectRetain(node)
            return node
        }
        var child: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(node, kIOServicePlane, &child) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(child) }
        var c = IOIteratorNext(child)
        while c != 0 {
            if let found = findAccelerator(under: c) { IOObjectRelease(c); return found }
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
        // 活跃度取各引擎单元利用率的最大值（更贴近“瞬时繁忙”）；无则回退整体利用率
        let units = [i("Device Unit 0 Utilization %"), i("Device Unit 1 Utilization %"),
                     i("Device Unit 2 Utilization %"), i("Device Unit 3 Utilization %")].compactMap { $0 }
        s.activityPct = units.max() ?? util
        // gartUsedBytes 作为共享内存占用的可靠代理（inUseSysMemoryBytes 常为回绕的异常大值，不用）。
        if let gart = i("gartUsedBytes"), gart > 0 { s.vramInUseMB = gart / 1_048_576 }
        return s
    }

    // MARK: - 工具

    /// 从子树里的 IntelAccelerator 读取共享显存上限（VRAM,totalMB）。
    private func acceleratorVRAM(under node: io_object_t) -> Int? {
        if let cls = ioClassName(node), cls == "IntelAccelerator",
           let v = IORegistryEntryCreateCFProperty(node, "VRAM,totalMB" as CFString,
                                                   kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
            return v
        }
        var child: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(node, kIOServicePlane, &child) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(child) }
        var c = IOIteratorNext(child)
        while c != 0 {
            if let v = acceleratorVRAM(under: c) { IOObjectRelease(c); return v }
            IOObjectRelease(c)
            c = IOIteratorNext(child)
        }
        return nil
    }

    private func hasIntelAccelerator(under node: io_object_t) -> Bool {        if let cls = ioClassName(node), cls == "IntelAccelerator" { return true }
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
    /// 设备列表是静态信息，进程内枚举一次即可。
    private static let allMetalDevices = MTLCopyAllDevices()

    private func metalSupport(registryID: UInt64?) -> String? {
        let devices = Self.allMetalDevices
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
