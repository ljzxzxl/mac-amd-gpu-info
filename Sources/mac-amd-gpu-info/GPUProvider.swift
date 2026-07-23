import Foundation
import IOKit
import Metal

protocol GPUProvider {
    func readAllInfos() -> [GPUInfo]
    func readInfo() -> GPUInfo
    func readStats() -> GPUStats?
    func readStats(pciRegistryID: UInt64) -> GPUStats?
}

enum GPUReader {
    static let provider: GPUProvider = {
        if AppleSiliconGPUProvider.isSupported() {
            return AppleSiliconGPUProvider()
        }
        return AMDGPUProvider()
    }()

    static func readAllInfos() -> [GPUInfo] { return provider.readAllInfos() }
    static func readInfo() -> GPUInfo { return provider.readInfo() }
    static func readStats() -> GPUStats? { return provider.readStats() }
    static func readStats(pciRegistryID: UInt64) -> GPUStats? { return provider.readStats(pciRegistryID: pciRegistryID) }
}
