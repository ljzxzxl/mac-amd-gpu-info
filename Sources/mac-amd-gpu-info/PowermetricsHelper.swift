import Foundation

class PowermetricsHelper {
    static let shared = PowermetricsHelper()
    
    private(set) var isAuthorized = false
    private let outPath = "/tmp/mac_gpu_info_metrics.txt"
    
    func startIfNeeded() {
        if !AppleSiliconGPUProvider.isSupported() { return }
        
        if FileManager.default.fileExists(atPath: outPath) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: outPath),
               let date = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(date) < 5 {
                isAuthorized = true
                return
            }
        }
        
        try? FileManager.default.removeItem(atPath: outPath)
        
        let script = "do shell script \"echo '#!/bin/bash\\nwhile true; do /usr/bin/powermetrics --samplers gpu_power -n 1 -i 1000 > /tmp/mac_gpu_info_metrics.txt.tmp; mv /tmp/mac_gpu_info_metrics.txt.tmp /tmp/mac_gpu_info_metrics.txt; sleep 0.5; done' > /tmp/mac_gpu_helper.sh && chmod +x /tmp/mac_gpu_helper.sh && /tmp/mac_gpu_helper.sh >/dev/null 2>&1 &\" with prompt \"Mac GPU Info 申请提权以实时采集 Apple Silicon 高级频率和功耗数据\" with administrator privileges"
        
        DispatchQueue.global().async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                // Ignore the hanging nature by assuming if it starts writing the file, it worked.
                appleScript.executeAndReturnError(&error)
            }
        }
        
        // Polling the file creation to dynamically set isAuthorized to true
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
        
        if let range = content.range(of: "GPU Power: ") {
            let sub = content[range.upperBound...]
            if let end = sub.range(of: " mW") {
                let valStr = String(sub[..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
                if let mw = Double(valStr) {
                    stats.powerW = mw / 1000.0
                }
            }
        }
        
        if let range = content.range(of: "active frequency: ") {
            let sub = content[range.upperBound...]
            if let end = sub.range(of: " MHz") {
                let valStr = String(sub[..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
                if let mhz = Int(valStr) {
                    stats.coreMHz = mhz
                }
            }
        }
    }
}