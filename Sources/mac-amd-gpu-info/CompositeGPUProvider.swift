import Foundation

/// 聚合多个 GPUProvider：合并各自的显卡列表，并按 registryID 把传感器读取路由到对应 provider。
/// 用于 Intel Mac 上同时呈现 AMD 独显与 Intel 核显。
struct CompositeGPUProvider: GPUProvider {
    let providers: [GPUProvider]

    func readAllInfos() -> [GPUInfo] {
        providers.flatMap { $0.readAllInfos() }
    }

    func readInfo() -> GPUInfo {
        readAllInfos().first ?? providers.first!.readInfo()
    }

    func readStats() -> GPUStats? {
        for p in providers { if let s = p.readStats() { return s } }
        return nil
    }

    func readStats(pciRegistryID: UInt64) -> GPUStats? {
        for p in providers { if let s = p.readStats(pciRegistryID: pciRegistryID) { return s } }
        return nil
    }
}
