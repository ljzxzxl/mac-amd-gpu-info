import AppKit

final class MainWindowController: NSWindowController {
    private let infoVC = InfoTabViewController()
    private let sensorsVC = SensorsTabViewController()
    private let statusVC = StatusBarTabViewController()

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

        let statusItem = NSTabViewItem(identifier: "statusbar")
        statusItem.label = "状态栏"
        statusItem.viewController = statusVC

        tabView.addTabViewItem(infoItem)
        tabView.addTabViewItem(sensorItem)
        tabView.addTabViewItem(statusItem)
        window.contentView?.addSubview(tabView)
        tabView.layoutSubtreeIfNeeded()

        _ = infoVC.view
        infoVC.info = GPUReader.readInfo()

        var chrome: CGFloat = 40
        let contentRect = tabView.contentRect
        if contentRect.height > 0 { chrome = tabView.frame.height - contentRect.height }

        var winH = infoVC.preferredTabContentHeight + chrome + 6
        if let visible = NSScreen.main?.visibleFrame.height {
            winH = min(winH, visible - 60)
        }
        winH = max(winH, 480)
        window.setContentSize(NSSize(width: 560, height: winH))
        window.center()

        _ = sensorsVC.view
        sensorsVC.start()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
