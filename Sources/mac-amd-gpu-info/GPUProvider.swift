import Foundation
import IOKit
import Metal

protocol GPUProvider {
    func readAllInfos() -> [GPUInfo]
    func readInfo() -> GPUInfo
    func readStats() -> GPUStats?
    func readStats(pciRegistryID: UInt64) -> GPUStats?
}

/// IOKit 默认主端口。`kIOMasterPortDefault` 自 macOS 12 起废弃、更名为 `kIOMainPortDefault`，
/// 但新符号带 12.0 可用性标注，与本项目 11.0 的部署目标冲突；两者取值都是 MACH_PORT_NULL(0)，
/// 传 0 即表示“使用默认端口”，在全部支持版本上等价。
let kIOPortDefault: mach_port_t = 0

/// accelerator 服务句柄缓存（键为所属 PCI 节点的 registryID）。
///
/// GPU 拓扑在运行期基本不变，而传感器是 1~2Hz 轮询：每次都 `IOServiceGetMatchingServices` +
/// 子树递归属于纯浪费。属性读取失败（休眠恢复、eGPU 拔出）时调用方移除条目，下次自动重建。
final class AcceleratorCache {
    static let shared = AcceleratorCache()
    private init() {}

    private var map: [UInt64: io_object_t] = [:]
    private let lock = NSLock()

    func service(for key: UInt64) -> io_object_t? {
        lock.lock(); defer { lock.unlock() }
        return map[key]
    }

    /// 接管 service 的一次引用计数（调用方不再 release）。
    func store(_ service: io_object_t, for key: UInt64) {
        lock.lock(); defer { lock.unlock() }
        if let old = map[key] { IOObjectRelease(old) }
        map[key] = service
    }

    func invalidate(_ key: UInt64) {
        lock.lock(); defer { lock.unlock() }
        if let old = map.removeValue(forKey: key) { IOObjectRelease(old) }
    }
}

enum GPUReader {
    static let provider: GPUProvider = {
        if AppleSiliconGPUProvider.isSupported() {
            return AppleSiliconGPUProvider()
        }
        // Intel Mac：同时呈现 AMD 独显与 Intel 核显。
        return CompositeGPUProvider(providers: [AMDGPUProvider(), IntelGPUProvider()])
    }()

    static func readAllInfos() -> [GPUInfo] { return provider.readAllInfos() }
    static func readInfo() -> GPUInfo { return provider.readInfo() }
    static func readStats() -> GPUStats? { return provider.readStats() }
    static func readStats(pciRegistryID: UInt64) -> GPUStats? { return provider.readStats(pciRegistryID: pciRegistryID) }
}
