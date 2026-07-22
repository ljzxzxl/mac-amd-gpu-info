import Foundation

/// 多显卡场景下的"当前选中卡"共享源，供信息页 / 传感器页 / 状态栏统一读取。
final class GPUSelection {
    static let shared = GPUSelection()
    private init() {}

    private(set) var gpus: [GPUInfo] = []
    /// 当前选中卡的 PCI registryID；nil 表示回退到首张。
    var currentRegistryID: UInt64?

    func setGPUs(_ list: [GPUInfo]) {
        gpus = list
        if currentRegistryID == nil || !list.contains(where: { $0.registryID == currentRegistryID }) {
            currentRegistryID = list.first?.registryID
        }
    }

    var currentInfo: GPUInfo? {
        gpus.first { $0.registryID == currentRegistryID } ?? gpus.first
    }

    /// 供状态栏取选中卡传感器；无选中时回退首张。
    func readSelectedStats() -> GPUStats? {
        if let rid = currentRegistryID ?? gpus.first?.registryID {
            return GPUReader.readStats(pciRegistryID: rid)
        }
        return GPUReader.readStats()
    }
}
