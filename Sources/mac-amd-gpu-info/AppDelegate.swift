import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?
    private var statusBar: StatusBarController!
    private let appName = "Mac AMD GPU Info"
    // 版本号统一从 Bundle 的 CFBundleShortVersionString 读取，避免与 Info.plist/VERSION 漂移。
    private let versionString = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.2"

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = img
        }

        statusBar = StatusBarController()
        statusBar.onOpenWindow = { [weak self] in self?.showMainWindow() }

        // 启动形态判定：开启状态栏 + 自启动 + 非激活（登录拉起）→ 纯状态栏模式，不弹窗
        let launchedInBackground = !NSApp.isActive
        let settings = StatusBarSettings.shared
        if settings.enabled && settings.autostart && launchedInBackground {
            NSApp.setActivationPolicy(.accessory)
        } else {
            showMainWindow()
        }
    }

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if windowController == nil {
            windowController = MainWindowController()
        }
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 状态栏开启时后台驻留（隐藏 Dock 图标），否则正常退出
        if StatusBarSettings.shared.enabled {
            NSApp.setActivationPolicy(.accessory)
            return false
        }
        return true
    }

    // MARK: - 菜单

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
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
