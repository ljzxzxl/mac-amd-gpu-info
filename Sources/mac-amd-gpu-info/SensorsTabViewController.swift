import AppKit

/// 传感器页：顶部实时数值（与信息页同款输入框样式）+ 六张带含义备注的曲线。
final class SensorsTabViewController: NSViewController {

    private struct Metric {
        let label: String
        let box: CopyableLabel
        let get: (GPUStats) -> String
    }

    private let topView = FlippedView()
    private var isAppleSilicon = false
    private var authButtons: [NSButton] = []
    private var metrics: [Metric] = []

    private let stack = NSStackView()
    private let gTemp = SensorGraphView()
    private let gAct = SensorGraphView()
    private let gUtil = SensorGraphView()
    private let gPower = SensorGraphView()
    private let gFan = SensorGraphView()
    private let gVRAM = SensorGraphView()
    private var timer: Timer?

    private var vramTotalMB = 4096.0
    private var selectedRegistryID: UInt64?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 600))

        // 顶部实时数值网格（输入框样式，与信息页统一）
        topView.frame = NSRect(x: 12, y: 508, width: 536, height: 84)
        topView.autoresizingMask = [.width, .minYMargin]
        container.addSubview(topView)

        buildMetrics()
        layoutMetrics()

        // 曲线区
        stack.orientation = .vertical
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.frame = NSRect(x: 12, y: 12, width: 536, height: 488)
        stack.autoresizingMask = [.width, .height]
        for g in [gTemp, gAct, gUtil, gPower, gFan, gVRAM] {
            g.wantsLayer = true
            g.layer?.borderWidth = 1
            g.layer?.borderColor = NSColor.gridColor.cgColor
            g.layer?.cornerRadius = 4
            stack.addArrangedSubview(g)
        }
        container.addSubview(stack)

        gTemp.configure([GraphSeries(label: "温度", color: .systemRed, maxValue: 100, unit: "°C")])
        gTemp.note = "GPU 核心温度"
        gAct.configure([GraphSeries(label: "GPU 活跃度", color: .systemBlue, maxValue: 100, unit: "%")])
        gAct.note = "瞬时引擎繁忙度（采样值，会跳动）"
        gUtil.configure([GraphSeries(label: "占用", color: .systemTeal, maxValue: 100, unit: "%")])
        gUtil.note = "设备占用（时间窗口平均，较平滑）"
        gPower.configure([GraphSeries(label: "功耗", color: .systemOrange, maxValue: 250, unit: "W")])
        gPower.note = "整卡总功耗"
        gFan.configure([GraphSeries(label: "风扇", color: .systemGreen, maxValue: 2500, unit: "RPM")])
        gFan.note = "显卡风扇转速"
        configureVRAMGraph()

        self.view = container
    }

    /// 按当前选中卡的显存容量设置显存曲线上限与备注。
    private func configureVRAMGraph() {
        gVRAM.configure([GraphSeries(label: "显存占用", color: .systemPurple, maxValue: vramTotalMB, unit: "MB")])
        gVRAM.note = "已用显存 / \(Int(vramTotalMB)) MB"
    }

    /// 主窗口下拉框切换显卡时调用：更新目标卡与显存上限并立即刷新。
    func setSelectedGPU(_ info: GPUInfo?) {
        selectedRegistryID = info?.registryID
        isAppleSilicon = info?.isAppleSilicon ?? false
        vramTotalMB = Double(info?.vramMB ?? 4096)
        guard isViewLoaded else { return }
        
        topView.subviews.forEach { $0.removeFromSuperview() }
        buildMetrics()
        layoutMetrics()
        
        configureVRAMGraph()
        refresh()
    }


    private func buildMetrics() {
        func f(_ v: Int?, _ u: String) -> String { v.map { "\($0) \(u)" } ?? "-" }
        func fD(_ v: Double?, _ u: String) -> String { v.map { $0 < 1.0 ? "\(Int($0*1000)) mW" : String(format: "%.1f W", $0) } ?? "-" }
        var list: [Metric] = [
            Metric(label: "温度", box: UI.valueBox("-")) { f($0.tempC, "°C") },
            Metric(label: "核心频率", box: UI.valueBox("-")) { f($0.coreMHz, "MHz") }
        ]
        list.append(Metric(label: "显存频率", box: UI.valueBox("-")) { f($0.memMHz, "MHz") })
        list.append(contentsOf: [
            Metric(label: "活跃", box: UI.valueBox("-")) { f($0.activityPct, "%") },
            Metric(label: "占用", box: UI.valueBox("-")) { f($0.deviceUtilPct, "%") },
            Metric(label: "功耗", box: UI.valueBox("-")) { fD($0.powerW, "W") },
            Metric(label: "风扇", box: UI.valueBox("-")) { "\(f($0.fanRPM, "RPM"))\($0.fanPct.map { " (\($0)%)" } ?? "")" },
            Metric(label: "显存占用", box: UI.valueBox("-")) { f($0.vramInUseMB, "MB") }
        ])
        metrics = list
    }

    private func layoutMetrics() {
        authButtons.forEach { $0.removeFromSuperview() }
        authButtons.removeAll()
        
        let cols = 3
        let cellW = topView.frame.width / CGFloat(cols)
        for (i, m) in metrics.enumerated() {
            let r = i / cols, c = i % cols
            let x = CGFloat(c) * cellW
            let yy = CGFloat(r) * 26 + 4
            let lab = UI.label(m.label, size: 11, color: .secondaryLabelColor)
            lab.frame = NSRect(x: x, y: yy + 3, width: 42, height: 15)
            topView.addSubview(lab)
            m.box.frame = NSRect(x: x + 44, y: yy, width: cellW - 50, height: 21)
            topView.addSubview(m.box)
            
            if isAppleSilicon && (m.label == "核心频率" || m.label == "功耗") {
                let btn = NSButton(title: "点击授权", target: self, action: #selector(doAuth))
                btn.bezelStyle = .inline
                btn.font = NSFont.systemFont(ofSize: 10)
                if #available(macOS 11.0, *) {
                    btn.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
                    btn.imagePosition = .imageLeft
                    btn.frame = NSRect(x: x + 44, y: yy + 1, width: 75, height: 18)
                } else {
                    btn.frame = NSRect(x: x + 46, y: yy + 3, width: 60, height: 15)
                }
                topView.addSubview(btn)
                authButtons.append(btn)
            }
        }
    }

    func start() {
        refresh()
        let t = Timer(timeInterval: 1.0, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
        
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSNotification.Name("PowermetricsAuthorized"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func refresh() {
        guard isViewLoaded else { return }
        let stats = selectedRegistryID.map { GPUReader.readStats(pciRegistryID: $0) } ?? GPUReader.readStats()
        let isAuth = PowermetricsHelper.shared.isAuthorized
        authButtons.forEach { $0.isHidden = isAuth }
        
        for m in metrics {
            var v = stats.map { m.get($0) } ?? "-"
            if isAppleSilicon {
                if !isAuth && (m.label == "核心频率" || m.label == "功耗") {
                    v = ""
                }
            }
            m.box.stringValue = v
            m.box.toolTip = v
        }
        let s = stats ?? GPUStats()
        gTemp.push([s.tempC.map(Double.init)])
        gAct.push([s.activityPct.map(Double.init)])
        gUtil.push([s.deviceUtilPct.map(Double.init)])
        gPower.push([s.powerW])
        gFan.push([s.fanRPM.map(Double.init)])
        gVRAM.push([s.vramInUseMB.map(Double.init)])
    }
    @objc private func doAuth() { PowermetricsHelper.shared.startIfNeeded() }
}
