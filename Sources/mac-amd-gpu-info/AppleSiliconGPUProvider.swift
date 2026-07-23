import Foundation
import IOKit
import Metal

struct AppleSiliconGPUProvider: GPUProvider {
    
    static func isSupported() -> Bool {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(it) }
        var service = IOIteratorNext(it)
        while service != 0 {
            if let cls = ioClassName(service), cls.contains("AGXAccelerator") {
                IOObjectRelease(service)
                return true
            }
            IOObjectRelease(service)
            service = IOIteratorNext(it)
        }
        return false
    }

    func readAllInfos() -> [GPUInfo] {
        var result: [GPUInfo] = []
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(it) }
        var service = IOIteratorNext(it)
        while service != 0 {
            if let cls = Self.ioClassName(service), cls.contains("AGXAccelerator") {
                var info = GPUInfo(modelName: "Apple Silicon GPU")
                info.isAppleSilicon = true
                info.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
                info.metalSupport = metalSupport()
                info.driver = "Apple AGX (\(cls))"
                
                info.vendorID = 0x106B // Apple
                info.brand = "Apple"
                info.pcieLink = "SoC 内部总线"
                
                if let dev = MTLCreateSystemDefaultDevice() {
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
                
                let memSize = ProcessInfo.processInfo.physicalMemory
                info.vramMB = Int(memSize / 1_048_576)
                info.vramType = "Unified Memory"
                info.memoryVendor = "Apple LPDDR"
                
                var rid: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(service, &rid) == KERN_SUCCESS {
                    info.registryID = rid
                }
                
                result.append(info)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(it)
        }
        return result
    }

    func readInfo() -> GPUInfo {
        return readAllInfos().first ?? {
            var info = GPUInfo(modelName: "未检测到 Apple Silicon GPU")
            info.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            info.metalSupport = metalSupport()
            return info
        }()
    }

    func readStats() -> GPUStats? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(it) }
        var service = IOIteratorNext(it)
        while service != 0 {
            if let cls = Self.ioClassName(service), cls.contains("AGXAccelerator") {
                let stats = parseStats(service)
                IOObjectRelease(service)
                return stats
            }
            IOObjectRelease(service)
            service = IOIteratorNext(it)
        }
        return nil
    }

    func readStats(pciRegistryID: UInt64) -> GPUStats? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, IORegistryEntryIDMatching(pciRegistryID), &it) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(it) }
        let service = IOIteratorNext(it)
        if service != 0 {
            let stats = parseStats(service)
            IOObjectRelease(service)
            return stats
        }
        return nil
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
        
        // 读取免 Root SMC 温度 (M 芯片的 SoC / GPU Package 综合温度)
        if let maxTemp = SMCReader.readMaxDieTemperature() {
            s.tempC = Int(maxTemp)
        }
        
        // 尝试从高级授权辅助程序中读取频率和功耗
        PowermetricsHelper.shared.fillStats(&s)
        
        return s
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
    
    private static func ioClassName(_ service: io_object_t) -> String? {
        var name = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(service, &name) == KERN_SUCCESS else { return nil }
        return String(cString: name)
    }
}

/// 封装 IOHIDEventSystemClient 读取 SoC 核心温度（无需 Root）
struct SMCReader {
    static func readMaxDieTemperature() -> Double? {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return nil }
        
        let _Create = unsafeBitCast(dlsym(iokit, "IOHIDEventSystemClientCreate"), to: (@convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?).self)
        let _CopyServices = unsafeBitCast(dlsym(iokit, "IOHIDEventSystemClientCopyServices"), to: (@convention(c) (UnsafeMutableRawPointer) -> CFArray?).self)
        let _CopyProperty = unsafeBitCast(dlsym(iokit, "IOHIDServiceClientCopyProperty"), to: (@convention(c) (UnsafeMutableRawPointer, CFString) -> CFTypeRef?).self)
        let _CopyEvent = unsafeBitCast(dlsym(iokit, "IOHIDServiceClientCopyEvent"), to: (@convention(c) (UnsafeMutableRawPointer, Int64, Int32, Int64) -> UnsafeMutableRawPointer?).self)
        let _GetFloatValue = unsafeBitCast(dlsym(iokit, "IOHIDEventGetFloatValue"), to: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Double).self)
        
        guard let client = _Create(nil) else { return nil }
        guard let servicesCF = _CopyServices(client) else { return nil }
        let numServices = CFArrayGetCount(servicesCF)
        
        var maxTemp: Double = 0.0
        
        for i in 0..<numServices {
            let service = CFArrayGetValueAtIndex(servicesCF, i)!
            let servicePtr = UnsafeMutableRawPointer(mutating: service)
            
            if let productCF = _CopyProperty(servicePtr, "Product" as CFString), let product = productCF as? String {
                if product.lowercased().contains("tdie") {
                    if let event = _CopyEvent(servicePtr, 15, 0, 0) { // 15 = kIOHIDEventTypeTemperature
                        let temp = _GetFloatValue(event, (15 << 16) | 0)
                        if temp > maxTemp && temp < 150 {
                            maxTemp = temp
                        }
                    }
                }
            }
        }
        return maxTemp > 0 ? maxTemp : nil
    }
}
