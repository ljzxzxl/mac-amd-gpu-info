import Foundation
import IOKit
import Metal

struct AppleSiliconGPUProvider: GPUProvider {

    /// AGXAccelerator 服务句柄常驻缓存：SoC 内置 GPU 不会热插拔，无需每次采集重扫 IORegistry。
    private static let agx: (service: io_service_t, className: String, registryID: UInt64)? = {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(it) }
        var service = IOIteratorNext(it)
        while service != 0 {
            if let cls = ioClassName(service), cls.contains("AGXAccelerator") {
                var rid: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(service, &rid)
                return (service, cls, rid)   // 长期持有，不释放
            }
            IOObjectRelease(service)
            service = IOIteratorNext(it)
        }
        return nil
    }()

    /// GPU 型号与 Metal 支持等级是静态信息，进程内采集一次即可。
    private static let metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

    private static let metalSupportLabel: String? = {
        guard let dev = metalDevice else { return nil }
#if arch(arm64)
        if #available(macOS 15.0, *) {
            // 用 rawValue 规避旧 SDK 无 MTLGPUFamily.apple9 枚举导致的编译失败（apple9 == 1009）
            if let apple9 = MTLGPUFamily(rawValue: 1009), dev.supportsFamily(apple9) { return "Metal 4" }
        }
#endif
        if #available(macOS 13.0, *) {
            if dev.supportsFamily(.metal3) { return "Metal 3" }
        }
        return "Metal (\(dev.name))"
    }()

    static func isSupported() -> Bool { agx != nil }

    func readAllInfos() -> [GPUInfo] {
        guard let agx = Self.agx else { return [] }
        let service = agx.service

        var info = GPUInfo(modelName: "Apple Silicon GPU")
        info.isAppleSilicon = true
        info.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        info.metalSupport = Self.metalSupportLabel
        info.driver = "Apple AGX (\(agx.className))"

        info.vendorID = 0x106B // Apple
        info.brand = "Apple"
        info.pcieLink = "SoC 内部总线"
        info.registryID = agx.registryID

        if let dev = Self.metalDevice {
            info.modelName = dev.name
            info.chip = dev.name.components(separatedBy: " ").last
        }

        if let config = IORegistryEntryCreateCFProperty(service, "GPUConfigurationVariable" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
           let gen = config["gpu_gen"] as? Int {
            info.architecture = "Apple G\(gen) (TBDR)"
            switch gen {
            case 13: info.process = "5nm"; info.transistorsB = 16.0
            case 14: info.process = "5nm"; info.transistorsB = 20.0
            case 15: info.process = "3nm"; info.transistorsB = 25.0
            case 16: info.process = "3nm"; info.transistorsB = 28.0
            case 17: info.process = "3nm"; info.transistorsB = 30.0
            default: info.process = "3nm"
            }
        } else {
            info.architecture = "Apple (TBDR)"
        }

        if let coreCount = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
            info.computeUnits = coreCount.intValue
            info.shaders = coreCount.intValue * 128
        }

        info.vramMB = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
        info.vramType = "Unified Memory"
        info.memoryVendor = "Apple LPDDR"

        return [info]
    }

    func readInfo() -> GPUInfo {
        return readAllInfos().first ?? {
            var info = GPUInfo(modelName: "未检测到 Apple Silicon GPU")
            info.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            info.metalSupport = Self.metalSupportLabel
            return info
        }()
    }

    func readStats() -> GPUStats? {
        guard let agx = Self.agx else { return nil }
        return parseStats(agx.service)
    }

    func readStats(pciRegistryID: UInt64) -> GPUStats? {
        guard let agx = Self.agx, agx.registryID == pciRegistryID else { return nil }
        return parseStats(agx.service)
    }

    private func parseStats(_ service: io_object_t) -> GPUStats {
        var s = GPUStats()
        if let perf = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
            if let util = perf["Device Utilization %"] as? NSNumber {
                s.deviceUtilPct = util.intValue
                s.activityPct = util.intValue
            }
            if let inUse = perf["In use system memory"] as? NSNumber {
                s.vramInUseMB = inUse.intValue / 1_048_576
            }
        }

        // 免 Root SMC 温度（M 芯片的 SoC / GPU Package 综合温度）
        if let maxTemp = SMCReader.readMaxDieTemperature() {
            s.tempC = Int(maxTemp)
        }

        // 免 Root 的功耗与活跃频率（IOReport，powermetrics 的底层数据源）
        let sample = IOReportGPUSampler.shared.read()
        if let w = sample.powerW { s.powerW = w }
        if let mhz = sample.coreMHz { s.coreMHz = mhz }

        return s
    }

    private static func ioClassName(_ service: io_object_t) -> String? {
        var name = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(service, &name) == KERN_SUCCESS else { return nil }
        return String(cString: name)
    }
}

/// 封装 IOHIDEventSystemClient 读取 SoC 核心温度（无需 Root）。
///
/// client 与温度服务列表首次使用时建立并常驻：原先每次采集都 dlopen + 新建 client + 全量枚举 HID 服务，
/// 且 CopyEvent 返回的事件对象未释放，1Hz 采集下会持续泄漏。
final class SMCReader {
    private static let shared = SMCReader()

    static func readMaxDieTemperature() -> Double? { shared?.readMaxDie() }

    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (UnsafeMutableRawPointer, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (UnsafeMutableRawPointer, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias FloatValueFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Double

    private static let temperatureEventType: Int64 = 15   // kIOHIDEventTypeTemperature

    private let copyEvent: CopyEventFn
    private let floatValue: FloatValueFn
    /// client 与 servicesArray 必须与服务指针同生命周期：client 一旦释放，
    /// 其下的 service client 的 mach port 即失效，再取事件会 SIGSEGV。
    private let client: AnyObject
    private let servicesArray: CFArray
    /// 命中 "tdie" 的温度服务（由 servicesArray 持有所有权）。
    private let dieServices: [UnsafeMutableRawPointer]
    private let lock = NSLock()

    private init?() {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let pCreate = dlsym(iokit, "IOHIDEventSystemClientCreate"),
              let pServices = dlsym(iokit, "IOHIDEventSystemClientCopyServices"),
              let pProperty = dlsym(iokit, "IOHIDServiceClientCopyProperty"),
              let pEvent = dlsym(iokit, "IOHIDServiceClientCopyEvent"),
              let pFloat = dlsym(iokit, "IOHIDEventGetFloatValue")
        else { return nil }

        let create = unsafeBitCast(pCreate, to: CreateFn.self)
        let copyServices = unsafeBitCast(pServices, to: CopyServicesFn.self)
        let copyProperty = unsafeBitCast(pProperty, to: CopyPropertyFn.self)
        copyEvent = unsafeBitCast(pEvent, to: CopyEventFn.self)
        floatValue = unsafeBitCast(pFloat, to: FloatValueFn.self)

        guard let hidClient = create(nil)?.takeRetainedValue(),
              let services = copyServices(hidClient)?.takeRetainedValue() else { return nil }
        client = hidClient
        servicesArray = services

        var matched: [UnsafeMutableRawPointer] = []
        for i in 0..<CFArrayGetCount(services) {
            guard let raw = CFArrayGetValueAtIndex(services, i) else { continue }
            let svc = UnsafeMutableRawPointer(mutating: raw)
            guard let product = copyProperty(svc, "Product" as CFString)?.takeRetainedValue() as? String,
                  product.lowercased().contains("tdie") else { continue }
            matched.append(svc)
        }
        dieServices = matched
    }

    private func readMaxDie() -> Double? {
        guard !dieServices.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }

        var maxTemp = 0.0
        for svc in dieServices {
            guard let event = copyEvent(svc, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else { continue }
            let temp = floatValue(Unmanaged.passUnretained(event).toOpaque(),
                                  Int32(Self.temperatureEventType << 16))
            if temp > maxTemp && temp < 150 { maxTemp = temp }
        }
        return maxTemp > 0 ? maxTemp : nil
    }
}
