import Foundation

/// 状态栏可显示的 8 个指标：状态栏前缀 + 明细文案 + 取值格式化。
enum StatusBarMetric: String, CaseIterable {
    case temp, fan, power, activity, util, vram, coreClk, memClk

    /// 设置页与明细菜单用的名称
    var title: String {
        switch self {
        case .temp: return "温度"
        case .fan: return "风扇转速"
        case .power: return "功耗"
        case .activity: return "GPU 活跃度"
        case .util: return "设备占用"
        case .vram: return "显存占用"
        case .coreClk: return "核心频率"
        case .memClk: return "显存频率"
        }
    }

    /// 状态栏并排显示用的单字前缀（区分多个百分比）
    var prefix: String {
        switch self {
        case .temp: return "温"
        case .fan: return "扇"
        case .power: return "功"
        case .activity: return "活"
        case .util: return "占"
        case .vram: return "显"
        case .coreClk: return "核"
        case .memClk: return "频"
        }
    }

    /// 状态栏紧凑文本；数据缺失返回 nil（不并入状态栏）
    func statusText(_ s: GPUStats) -> String? {
        switch self {
        case .temp: return s.tempC.map { "\(prefix)\($0)°C" }
        case .fan: return s.fanRPM.map { "\(prefix)\($0)" }
        case .power: return s.powerW.map { "\(prefix)\($0)W" }
        case .activity: return s.activityPct.map { "\(prefix)\($0)%" }
        case .util: return s.deviceUtilPct.map { "\(prefix)\($0)%" }
        case .vram: return s.vramInUseMB.map { "\(prefix)\($0)M" }
        case .coreClk: return s.coreMHz.map { "\(prefix)\($0)" }
        case .memClk: return s.memMHz.map { "\(prefix)\($0)" }
        }
    }

    /// 下拉菜单里的明细行
    func detailText(_ s: GPUStats) -> String {
        func f(_ v: Int?, _ u: String) -> String { v.map { "\($0) \(u)" } ?? "—" }
        switch self {
        case .temp: return "温度：\(f(s.tempC, "°C"))"
        case .fan: return "风扇：\(f(s.fanRPM, "RPM"))\(s.fanPct.map { " (\($0)%)" } ?? "")"
        case .power: return "功耗：\(f(s.powerW, "W"))"
        case .activity: return "GPU 活跃度：\(f(s.activityPct, "%"))"
        case .util: return "设备占用：\(f(s.deviceUtilPct, "%"))"
        case .vram: return "显存占用：\(f(s.vramInUseMB, "MB"))"
        case .coreClk: return "核心频率：\(f(s.coreMHz, "MHz"))"
        case .memClk: return "显存频率：\(f(s.memMHz, "MHz"))"
        }
    }
}
