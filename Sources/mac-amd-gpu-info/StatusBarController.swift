import AppKit

/// 状态栏控制器：按设置增删 NSStatusItem，每 2 秒刷新并排指标文本与下拉明细。
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private let settings = StatusBarSettings.shared
    private var detailItems: [StatusBarMetric: NSMenuItem] = [:]

    /// 由 AppDelegate 注入：点「打开主窗口」时的回调。
    var onOpenWindow: (() -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(apply),
                                               name: StatusBarSettings.didChange, object: nil)
        apply()
    }

    @objc func apply() {
        settings.enabled ? show() : hide()
    }

    private func show() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            statusItem = item
            buildMenu()
        }
        refresh()
        if timer == nil {
            let t = Timer(timeInterval: 2.0, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func hide() {
        timer?.invalidate(); timer = nil
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
        detailItems.removeAll()
    }

    private func buildMenu() {
        let menu = NSMenu()
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
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func openWindow() { onOpenWindow?() }

    @objc private func refresh() {
        guard let item = statusItem else { return }
        guard let s = GPUReader.readStats() else {
            item.button?.title = "无 AMD 显卡"
            detailItems.values.forEach { $0.title = "未检测到 AMD 独显" }
            return
        }
        let parts = settings.enabledMetrics.compactMap { $0.statusText(s) }
        item.button?.title = parts.isEmpty ? "GPU" : parts.joined(separator: " ")
        for m in StatusBarMetric.allCases { detailItems[m]?.title = m.detailText(s) }
    }
}
