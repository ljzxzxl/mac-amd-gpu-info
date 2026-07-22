import AppKit

final class MainWindowController: NSWindowController {
    private let infoVC = InfoTabViewController()
    private let sensorsVC = SensorsTabViewController()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Mac AMD GPU Info"
        super.init(window: window)

        let tabView = NSTabView(frame: window.contentView!.bounds)
        tabView.autoresizingMask = [.width, .height]

        let infoItem = NSTabViewItem(identifier: "info")
        infoItem.label = "信息"
        infoItem.viewController = infoVC

        let sensorItem = NSTabViewItem(identifier: "sensors")
        sensorItem.label = "传感器"
        sensorItem.viewController = sensorsVC

        tabView.addTabViewItem(infoItem)
        tabView.addTabViewItem(sensorItem)
        window.contentView?.addSubview(tabView)
        tabView.layoutSubtreeIfNeeded()

        // 读取信息（先强制加载 infoVC.view 以便渲染并得到内容高度）
        _ = infoVC.view
        infoVC.info = GPUReader.readInfo()

        // 标签条等窗口装饰占用的高度（实测，避免估算不准导致仍出现滚动条）
        var chrome: CGFloat = 40
        let contentRect = tabView.contentRect
        if contentRect.height > 0 { chrome = tabView.frame.height - contentRect.height }

        // 窗口高度自适应信息页内容，铺满不留滚动条；超屏则封顶
        var winH = infoVC.preferredTabContentHeight + chrome + 6
        if let visible = NSScreen.main?.visibleFrame.height {
            winH = min(winH, visible - 60)
        }
        winH = max(winH, 480)
        window.setContentSize(NSSize(width: 560, height: winH))
        window.center()

        // 传感器：强制加载其视图后立即开始轮询，使曲线从开机就采集（不必先切到该页）
        _ = sensorsVC.view
        sensorsVC.start()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
