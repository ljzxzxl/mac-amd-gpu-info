import AppKit

final class MainWindowController: NSWindowController {
    private let infoVC = InfoTabViewController()
    private let sensorsVC = SensorsTabViewController()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 580),
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
        window.center()

        // 静态信息读取一次
        infoVC.info = GPUReader.readInfo()
        // 传感器开始轮询
        sensorsVC.start()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
