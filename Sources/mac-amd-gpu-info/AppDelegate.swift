import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController!
    private let appName = "Mac AMD GPU Info"
    private let versionString = "1.0"

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 图标（运行时设置，确保即时生效）
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = img
        }

        windowController = MainWindowController()
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - 菜单

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // 应用菜单
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        appMenu.addItem(withTitle: "关于 \(appName)", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        let verItem = NSMenuItem(title: "版本 \(versionString)", action: nil, keyEquivalent: "")
        verItem.isEnabled = false
        appMenu.addItem(verItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        appMenu.items.forEach { if $0.action == #selector(showAbout) { $0.target = self } }

        return mainMenu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appName,
            .applicationVersion: versionString,
            NSApplication.AboutPanelOptionKey(rawValue: "Version"): versionString,
            .credits: NSAttributedString(
                string: "Intel Mac + AMD 独显信息与监控工具\n数据来自 IOKit，只读、不联网",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
    }
}
