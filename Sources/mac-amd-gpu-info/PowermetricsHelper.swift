import Foundation

/// 通过 powermetrics（需提权）采集实时高级指标：
/// - Apple Silicon：GPU 功耗 + GPU 实时频率
/// - Intel：CPU 实时平均频率（作为核显“核心频率”的实时来源，未授权则回退标称值）
class PowermetricsHelper {
    static let shared = PowermetricsHelper()

    private(set) var isAuthorized = false
    private let outPath = "/tmp/mac_gpu_info_metrics.txt"

    private var isAppleSilicon: Bool { AppleSiliconGPUProvider.isSupported() }

    /// 手动触发（按钮）或 Apple Silicon 启动时调用；会弹出一次管理员授权。
    func startIfNeeded() {
        if FileManager.default.fileExists(atPath: outPath) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: outPath),
               let date = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(date) < 5 {
                isAuthorized = true
                return
            }
        }

        try? FileManager.default.removeItem(atPath: outPath)

        let sampler = isAppleSilicon ? "gpu_power" : "cpu_power"
        let script = "do shell script \"echo '#!/bin/bash\\nwhile true; do /usr/bin/powermetrics --samplers \(sampler) -n 1 -i 1000 > /tmp/mac_gpu_info_metrics.txt.tmp; mv /tmp/mac_gpu_info_metrics.txt.tmp /tmp/mac_gpu_info_metrics.txt; sleep 0.5; done' > /tmp/mac_gpu_helper.sh && chmod +x /tmp/mac_gpu_helper.sh && /tmp/mac_gpu_helper.sh >/dev/null 2>&1 &\" with prompt \"Mac GPU Info 申请提权以实时采集频率/功耗数据\" with administrator privileges"

        DispatchQueue.global().async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        }

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if FileManager.default.fileExists(atPath: self.outPath) {
                self.isAuthorized = true
                NotificationCenter.default.post(name: NSNotification.Name("PowermetricsAuthorized"), object: nil)
                timer.invalidate()
            }
        }
    }

    func fillStats(_ stats: inout GPUStats) {
        guard isAuthorized else { return }
        guard let content = try? String(contentsOfFile: outPath, encoding: .utf8) else { return }

        if isAppleSilicon {
            if let range = content.range(of: "GPU Power: ") {
                let sub = content[range.upperBound...]
                if let end = sub.range(of: " mW") {
                    let valStr = String(sub[..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if let mw = Double(valStr) { stats.powerW = mw / 1000.0 }
                }
            }
            if let range = content.range(of: "active frequency: ") {
                let sub = content[range.upperBound...]
                if let end = sub.range(of: " MHz") {
                    let valStr = String(sub[..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if let mhz = Int(valStr) { stats.coreMHz = mhz }
                }
            }
        } else {
            // Intel：CPU 平均频率，形如 "CPU Average frequency as fraction of nominal: 78.53% (1186 MHz)"
            if let r = content.range(of: #"frequency as fraction of nominal:[^(]*\((\d+) MHz\)"#, options: .regularExpression) {
                let seg = content[r]
                if let mr = seg.range(of: #"\((\d+) MHz\)"#, options: .regularExpression) {
                    let digits = seg[mr].filter { $0.isNumber }
                    if let mhz = Int(digits) { stats.coreMHz = mhz }
                }
            }
        }
    }
}
