import AppKit

/// 传感器页：每秒轮询实时数值 + 温度/活跃度历史曲线。
final class SensorsTabViewController: NSViewController {

    private let valueField = NSTextField(labelWithString: "")
    private let graph = SensorGraphView(frame: .zero)
    private var timer: Timer?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 552))

        valueField.frame = NSRect(x: 16, y: 300, width: 508, height: 236)
        valueField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        valueField.maximumNumberOfLines = 0
        valueField.autoresizingMask = [.width, .minYMargin]
        valueField.lineBreakMode = .byWordWrapping
        container.addSubview(valueField)

        graph.frame = NSRect(x: 16, y: 16, width: 508, height: 270)
        graph.autoresizingMask = [.width, .height]
        graph.wantsLayer = true
        graph.layer?.borderWidth = 1
        graph.layer?.borderColor = NSColor.gridColor.cgColor
        container.addSubview(graph)

        self.view = container
    }

    func start() {
        refresh()
        let t = Timer(timeInterval: 1.0, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func refresh() {
        guard isViewLoaded else { return }
        guard let s = GPUReader.readStats() else {
            valueField.stringValue = "未检测到 AMD 独显（RadeonX4000 家族）"
            return
        }
        func f(_ v: Int?, _ unit: String) -> String { v.map { "\($0) \(unit)" } ?? "—" }
        let vram: String = {
            guard let used = s.vramInUseMB else { return "—" }
            return "\(used) MB 使用"
        }()

        valueField.stringValue = """
        温度        \(f(s.tempC, "°C"))
        核心频率    \(f(s.coreMHz, "MHz"))
        显存频率    \(f(s.memMHz, "MHz"))
        GPU 活跃度  \(f(s.activityPct, "%"))
        设备占用    \(f(s.deviceUtilPct, "%"))
        功耗        \(f(s.powerW, "W"))
        风扇        \(f(s.fanRPM, "RPM"))\(s.fanPct.map { " (\($0)%)" } ?? "")
        显存占用    \(vram)
        """

        graph.append(temp: s.tempC.map(Double.init), activity: s.activityPct.map(Double.init))
    }
}
