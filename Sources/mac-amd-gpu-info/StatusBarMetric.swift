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

    /// 状态栏两行样式里“下面那行”的英文缩写标签
    var abbr: String {
        switch self {
        case .temp: return "TEMP"
        case .fan: return "FAN"
        case .power: return "PWR"
        case .activity: return "ACT"
        case .util: return "UTIL"
        case .vram: return "VRAM"
        case .coreClk: return "CORE"
        case .memClk: return "MEM"
        }
    }

    /// 状态栏两行样式里“上面那行”的数值（分为 数字 和 单位，数据缺失返回 nil）
    func value(_ s: GPUStats) -> (num: String, unit: String)? {
        switch self {
        case .temp: return s.tempC.map { ("\($0)", "°C") }
        case .fan: return s.fanRPM.map { ("\($0)", "") }
        case .power: return s.powerW.map { $0 < 1.0 ? ("\(Int($0*1000))", "mW") : (String(format: "%.1f", $0), "W") }
        case .activity: return s.activityPct.map { ("\($0)", "%") }
        case .util: return s.deviceUtilPct.map { ("\($0)", "%") }
        case .vram: return s.vramInUseMB.map { ("\($0)", "M") }
        case .coreClk: return s.coreMHz.map { ("\($0)", "") }
        case .memClk: return s.memMHz.map { ("\($0)", "") }
        }
    }

    /// 下拉菜单里的明细行
    func detailText(_ s: GPUStats) -> String {
        func f(_ v: Int?, _ u: String) -> String { v.map { "\($0) \(u)" } ?? "-" }
        func fD(_ v: Double?, _ u: String) -> String { v.map { $0 < 1.0 ? "\(Int($0*1000)) mW" : String(format: "%.1f W", $0) } ?? "-" }
        switch self {
        case .temp: return "温度：\(f(s.tempC, "°C"))"
        case .fan: return "风扇：\(f(s.fanRPM, "RPM"))\(s.fanPct.map { " (\($0)%)" } ?? "")"
        case .power: return "功耗：\(fD(s.powerW, "W"))"
        case .activity: return "GPU 活跃度：\(f(s.activityPct, "%"))"
        case .util: return "设备占用：\(f(s.deviceUtilPct, "%"))"
        case .vram: return "显存占用：\(f(s.vramInUseMB, "MB"))"
        case .coreClk: return "核心频率：\(f(s.coreMHz, "MHz"))"
        case .memClk: return "显存频率：\(f(s.memMHz, "MHz"))"
        }
    }
}
