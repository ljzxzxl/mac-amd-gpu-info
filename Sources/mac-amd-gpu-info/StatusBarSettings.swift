import Foundation

/// 状态栏相关设置，持久化到 UserDefaults；变更时发通知。
final class StatusBarSettings {
    static let shared = StatusBarSettings()
    static let didChange = Notification.Name("StatusBarSettingsDidChange")

    private let d = UserDefaults.standard
    private let kEnabled = "statusbar.enabled"
    private let kAutostart = "statusbar.autostart"
    private func metricKey(_ m: StatusBarMetric) -> String { "statusbar.metric.\(m.rawValue)" }

    var enabled: Bool {
        get { d.object(forKey: kEnabled) as? Bool ?? false }
        set { d.set(newValue, forKey: kEnabled); notify() }
    }

    /// 仅记录用户意图；实际登录项状态以 LoginItem 为准
    var autostart: Bool {
        get { d.bool(forKey: kAutostart) }
        set { d.set(newValue, forKey: kAutostart) }
    }

    func isMetricOn(_ m: StatusBarMetric) -> Bool {
        d.object(forKey: metricKey(m)) as? Bool ?? defaultOn(m)
    }

    func setMetric(_ m: StatusBarMetric, _ on: Bool) {
        d.set(on, forKey: metricKey(m)); notify()
    }

    var enabledMetrics: [StatusBarMetric] {
        StatusBarMetric.allCases.filter { isMetricOn($0) }
    }

    private func defaultOn(_ m: StatusBarMetric) -> Bool {
        [.temp, .fan, .power].contains(m)     // 默认显示温度/风扇/功耗
    }

    private func notify() {
        NotificationCenter.default.post(name: StatusBarSettings.didChange, object: nil)
    }
}
