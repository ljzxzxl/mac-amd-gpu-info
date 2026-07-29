import Foundation

/// 仅用于 Intel 平台：借 powermetrics 采集 CPU 实时平均频率，作为核显「核心频率」的实时来源
/// （未授权时回退 IORegistry 的标称频率）。Apple Silicon 走 `IOReportGPUSampler`，无需提权。
///
/// 安全与生命周期约束（旧实现的三个缺陷已在此修正）：
/// - 不再往全局可写的 `/tmp` 落可执行脚本（`echo > /tmp/x.sh && chmod +x && 执行` 存在 TOCTOU 提权窗口）
/// - 输出改到当前用户私有的临时目录，且由 root 创建、普通用户只读，外部进程无法篡改数据
/// - 改为常驻单实例采样，并由 watchdog 轮询宿主 PID，应用退出即终止 root 进程并删除输出文件
///   （旧实现每 1.5s 冷启一个 powermetrics，父进程被 launchd 收养后永久残留）
final class PowermetricsHelper {
    static let shared = PowermetricsHelper()

    static let authorizedNotification = Notification.Name("PowermetricsAuthorized")

    /// 数据新鲜度阈值：超过该秒数未更新即认为 helper 已失效，降级为未授权。
    private static let staleTimeout: TimeInterval = 8
    /// powermetrics 最长驻留采样次数（1s 一次，约 1 小时），作为 watchdog 之外的兜底。
    private static let maxSamples = 3600

    private let outPath = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("mac-gpu-info-cpu-power.txt")

    private var didRequestAuthorization = false
    private var pollTimer: Timer?

    private init() {}

    /// 由核显传感器页的授权按钮触发；会弹出一次管理员授权。
    func startIfNeeded() {
        if isAuthorized || didRequestAuthorization { return }
        didRequestAuthorization = true

        let pid = ProcessInfo.processInfo.processIdentifier
        // 常驻单实例 + watchdog：应用进程消失后结束采样并清理文件。命令为固定文本，无外部输入拼接。
        let shell = "/usr/bin/powermetrics --samplers cpu_power -i 1000 -n \(Self.maxSamples) > '\(outPath)' 2>/dev/null & "
            + "PM=$!; (while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 2; done; "
            + "/bin/kill -9 $PM 2>/dev/null; /bin/rm -f '\(outPath)') >/dev/null 2>&1 &"
        let script = "do shell script \"\(shell)\""
            + " with prompt \"Mac GPU Info 申请提权以采集 CPU 实时频率\" with administrator privileges"

        DispatchQueue.global().async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            if error != nil {
                DispatchQueue.main.async { self.didRequestAuthorization = false }
            }
        }

        // powermetrics 首帧约需 1s；最多等待 30s，成功后通知 UI 立即刷新。
        var waited = 0.0
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            waited += 0.5
            if self.isAuthorized {
                timer.invalidate()
                self.pollTimer = nil
                NotificationCenter.default.post(name: Self.authorizedNotification, object: nil)
            } else if waited >= 30 {
                timer.invalidate()
                self.pollTimer = nil
                self.didRequestAuthorization = false
            }
        }
    }

    /// 真实心跳判定：输出文件必须存在且在 staleTimeout 内更新过，避免 helper 挂掉后误用陈旧数据。
    var isAuthorized: Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: outPath),
              let modified = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < Self.staleTimeout
    }

    /// 应用退出时调用：停止等待并尽力清理。root 侧的 powermetrics 与输出文件由 watchdog 回收。
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        didRequestAuthorization = false
        try? FileManager.default.removeItem(atPath: outPath)
    }

    func fillStats(_ stats: inout GPUStats) {
        guard isAuthorized, let tail = tailContent() else { return }
        // 形如 "CPU Average frequency as fraction of nominal: 78.53% (1186 MHz)"，取最新一条。
        guard let line = tail.range(of: #"frequency as fraction of nominal:[^\n]*\(\d+ MHz\)"#,
                                    options: [.regularExpression, .backwards]),
              let mhzRange = tail[line].range(of: #"\d+ MHz"#, options: .regularExpression),
              let mhz = Int(tail[line][mhzRange].prefix(while: { $0.isNumber })) else { return }
        stats.coreMHz = mhz
    }

    /// 只读文件尾部：powermetrics 常驻输出是追加写，全量读取会随时间线性变慢。
    private func tailContent(maxBytes: UInt64 = 8192) -> String? {
        guard let handle = FileHandle(forReadingAtPath: outPath) else { return nil }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        handle.seek(toFileOffset: size > maxBytes ? size - maxBytes : 0)
        return String(data: handle.readDataToEndOfFile(), encoding: .utf8)
    }

    // MARK: - 旧版本残留清理

    private static let legacyPaths = ["/tmp/mac_gpu_helper.sh",
                                      "/tmp/mac_gpu_info_metrics.txt",
                                      "/tmp/mac_gpu_info_metrics.txt.tmp"]

    /// v1.5.1 之前的 helper 会被 launchd 收养后永久残留，每次开机再叠加一份。
    static var hasLegacyLeftovers: Bool {
        !legacyPIDs().isEmpty || legacyPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// 找出旧版残留的 root 采集进程。pgrep 只读、无需提权；
    /// pattern 用方括号包首字母，避免匹配到承载本命令的 shell 自身。
    private static func legacyPIDs() -> [Int32] {
        var pids: [Int32] = []
        for pattern in ["[m]ac_gpu_helper", "[p]owermetrics --samplers gpu_power"] {
            let p = Process()
            p.launchPath = "/usr/bin/pgrep"
            p.arguments = ["-f", pattern]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            guard (try? p.run()) != nil else { continue }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            pids.append(contentsOf: text.split(whereSeparator: \.isNewline).compactMap { Int32($0) })
        }
        return Array(Set(pids))
    }

    /// 一次性清理旧版残留的 root 循环与 /tmp 文件。
    /// 用确切 PID + SIGKILL：`pkill -f` 会连带匹配到执行者自身，而这些进程对 SIGTERM
    /// 也不敏感（bash 在等待前台 powermetrics 时会延后处理信号）。
    static func cleanupLegacyLeftovers(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            var shell = ""
            let pids = legacyPIDs()
            if !pids.isEmpty {
                shell += "/bin/kill -9 \(pids.map(String.init).joined(separator: " ")) 2>/dev/null; "
            }
            shell += "/bin/rm -f \(legacyPaths.joined(separator: " "))"
            let script = "do shell script \"\(shell)\""
                + " with prompt \"Mac GPU Info 需要清理旧版本残留的后台采集进程\" with administrator privileges"

            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            // 被杀进程的回收与文件删除都不是瞬时的，稍等再校验。
            Thread.sleep(forTimeInterval: 1.0)
            let ok = error == nil && !hasLegacyLeftovers
            DispatchQueue.main.async { completion(ok) }
        }
    }
}
