import AppKit

/// 状态栏控制器：按设置增删 NSStatusItem，每 2 秒刷新并排指标文本与下拉明细。
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private let settings = StatusBarSettings.shared
    private var detailItems: [StatusBarMetric: NSMenuItem] = [:]

    /// 上一帧的列内容，用于数值未变化时跳过整张图的重建。
    private var lastColumns: [Column]?
    /// 菜单栏被全屏应用遮挡或屏幕休眠时无需采集与重绘。
    private var isOccluded = false

    private struct Column: Equatable {
        let value: String
        let label: String
    }

    // 字体与 attributes 为不变量，提到静态常量避免每帧重复构造。
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    private static let labelFont = NSFont.systemFont(ofSize: 7, weight: .medium)
    private static let valueAttrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: NSColor.black]
    private static let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.black]

    /// 由 AppDelegate 注入：点「打开主窗口」时的回调。
    var onOpenWindow: (() -> Void)?
    /// 由 AppDelegate 注入：点「检查更新…」时的回调。
    var onCheckUpdate: (() -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(apply),
                                               name: StatusBarSettings.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                               name: NSApplication.didChangeOcclusionStateNotification, object: nil)
        apply()
    }

    @objc func apply() {
        settings.enabled ? show() : hide()
    }

    @objc private func occlusionChanged() {
        isOccluded = !NSApp.occlusionState.contains(.visible)
        if !isOccluded { refresh(force: true) }
    }

    private func show() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            statusItem = item
            buildMenu()
        }
        lastColumns = nil
        refresh(force: true)
        if timer == nil {
            let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.refresh(force: false) }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func hide() {
        timer?.invalidate(); timer = nil
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
        detailItems.removeAll()
        lastColumns = nil
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        for m in StatusBarMetric.allCases {
            let it = NSMenuItem(title: m.title, action: nil, keyEquivalent: "")
            it.isEnabled = false
            detailItems[m] = it
            menu.addItem(it)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "打开主窗口", action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let check = NSMenuItem(title: "检查更新…", action: #selector(checkUpdate), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func openWindow() { onOpenWindow?() }
    @objc private func checkUpdate() { onCheckUpdate?() }

    /// 下拉打开时补一次采集，保证遮挡期间跳过刷新后明细仍是最新值。
    func menuWillOpen(_ menu: NSMenu) { refresh(force: true) }

    private func refresh(force: Bool) {
        guard let item = statusItem, let button = item.button else { return }
        guard force || !isOccluded else { return }

        guard let s = GPUSelection.shared.readSelectedStats() else {
            button.image = nil
            button.title = "未检测到支持的 GPU"
            detailItems.values.forEach { $0.title = "未检测到 GPU" }
            lastColumns = nil
            return
        }
        for m in StatusBarMetric.allCases { detailItems[m]?.title = m.detailText(s) }

        // 两行样式：每个开启指标一列，上值下缩写；整体绘成模板图精确竖直居中。
        let cols: [Column] = settings.enabledMetrics.compactMap { m in
            m.value(s).map { Column(value: $0.num + $0.unit, label: m.abbr) }
        }
        guard cols != lastColumns else { return }   // 数值未变化，不必重建图片
        lastColumns = cols

        if cols.isEmpty {
            button.image = nil
            button.title = "GPU"
        } else if let img = Self.makeStackedImage(cols) {
            button.title = ""
            button.image = img
            button.imagePosition = .imageOnly
        }
    }

    /// 把若干「上值 / 下缩写」两行列并排绘制成与菜单栏等高的模板图（参照 gpu-fan-monitor 两行效果）。
    /// 用 drawingHandler 交由系统惰性绘制，避免 lockFocus 主动创建离屏上下文。
    private static func makeStackedImage(_ cols: [Column]) -> NSImage? {
        guard !cols.isEmpty else { return nil }
        let height = NSStatusBar.system.thickness
        let colGap: CGFloat = 6
        let sidePad: CGFloat = 3

        var colWidths: [CGFloat] = []
        var valueSizes: [NSSize] = []
        var labelSizes: [NSSize] = []
        for c in cols {
            let vs = (c.value as NSString).size(withAttributes: valueAttrs)
            let ls = (c.label as NSString).size(withAttributes: labelAttrs)
            valueSizes.append(vs)
            labelSizes.append(ls)
            colWidths.append(ceil(max(vs.width, ls.width)))
        }
        let totalWidth = sidePad * 2 + colWidths.reduce(0, +) + colGap * CGFloat(cols.count - 1)

        let image = NSImage(size: NSSize(width: max(totalWidth, 1), height: height), flipped: false) { _ in
            let topLineH: CGFloat = 11, botLineH: CGFloat = 8, gap: CGFloat = -1
            // 整体略向下移（非翻转坐标 y 越小越靠下），修正视觉偏上；如需再调改此 nudge。
            let yNudge: CGFloat = -2
            let startY = ((height - (topLineH + botLineH + gap)) / 2).rounded() + yNudge
            // 分隔竖线：居中对齐两行文字的视觉中心（≈ startY+10），高 12px、上下对称
            let yBottom = startY + 4
            let yTop = startY + 16
            var x = sidePad
            for (i, c) in cols.enumerated() {
                let cw = colWidths[i]
                (c.label as NSString).draw(at: NSPoint(x: x + (cw - labelSizes[i].width) / 2, y: startY),
                                           withAttributes: labelAttrs)
                (c.value as NSString).draw(at: NSPoint(x: x + (cw - valueSizes[i].width) / 2,
                                                       y: startY + botLineH + gap),
                                           withAttributes: valueAttrs)
                // 指标之间画一条暗色分隔竖线（模板图下用低 alpha 实现“更暗”）
                if i < cols.count - 1 {
                    let dx = (x + cw + colGap / 2).rounded()
                    let line = NSBezierPath()
                    line.move(to: NSPoint(x: dx, y: yBottom))
                    line.line(to: NSPoint(x: dx, y: yTop))
                    line.lineWidth = 1
                    NSColor.black.withAlphaComponent(0.30).setStroke()
                    line.stroke()
                }
                x += cw + colGap
            }
            return true
        }
        image.isTemplate = true   // 跟随菜单栏明暗/高亮自动着色
        return image
    }
}
