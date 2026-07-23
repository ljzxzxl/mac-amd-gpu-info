import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?
    private var statusBar: StatusBarController!
    private let appName = "Mac GPU Info"
    // 版本号统一从 Bundle 的 CFBundleShortVersionString 读取，避免与 Info.plist/VERSION 漂移。
    private let versionString = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.4.0"

    private var isCheckingUpdate = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        // 启动时静默启动提权或请求提权（仅在 Apple Silicon 上）
        PowermetricsHelper.shared.startIfNeeded()

        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = img
        }

        statusBar = StatusBarController()
        statusBar.onOpenWindow = { [weak self] in self?.showMainWindow() }
        statusBar.onCheckUpdate = { [weak self] in self?.checkForUpdates(silent: false) }

        // 启动形态判定：开启状态栏 + 自启动 + 非激活（登录拉起）→ 纯状态栏模式，不弹窗
        let launchedInBackground = !NSApp.isActive
        let settings = StatusBarSettings.shared
        if settings.enabled && settings.autostart && launchedInBackground {
            NSApp.setActivationPolicy(.accessory)
        } else {
            showMainWindow()
        }

        // 启动静默检查更新（仅在有新版时弹窗）
        checkForUpdates(silent: true)
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
        if StatusBarSettings.shared.enabled {
            NSApp.setActivationPolicy(.accessory)
            return false
        }
        return true
    }

    // MARK: - 更新

    @objc private func checkForUpdatesMenu() { checkForUpdates(silent: false) }

    /// silent=true 用于启动检查（只有新版才弹窗）；false 用于手动检查（三态都反馈）。
    private func checkForUpdates(silent: Bool) {
        if isCheckingUpdate { return }
        isCheckingUpdate = true
        Updater.fetchLatest { [weak self] result in
            guard let self = self else { return }
            self.isCheckingUpdate = false
            switch result {
            case .success(let info):
                if Updater.isNewer(info.version, than: Updater.currentVersion) {
                    self.presentUpdate(info)
                } else if !silent {
                    self.info("已是最新版本（v\(Updater.currentVersion)）")
                }
            case .failure(let err):
                if !silent {
                    self.info("检查更新失败：\(err.localizedDescription)")
                }
            }
        }
    }

    private func presentUpdate(_ info: ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "发现新版本 v\(info.version)"
        alert.informativeText = "当前版本 v\(Updater.currentVersion)。是否下载更新？"
        alert.addButton(withTitle: "下载更新")
        alert.addButton(withTitle: "发行说明")
        alert.addButton(withTitle: "稍后")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let dmg = info.dmgURL {
                // 直接开始下载（不要在此前弹模态框——runModal 会阻塞主线程、延后下载启动，
                // 造成“提示在下载但实际没下载”的错觉）。成功后 DMG 会自动打开安装窗。
                Updater.downloadAndOpen(dmg) { [weak self] err in
                    guard let err = err else { return }
                    self?.info("下载失败：\(err.localizedDescription)\n将打开发行页，可手动下载。")
                    if let page = info.pageURL { NSWorkspace.shared.open(page) }
                }
            } else if let page = info.pageURL {
                NSWorkspace.shared.open(page)   // 无 dmg 资产则打开发行页
            }
        case .alertSecondButtonReturn:
            if let page = info.pageURL { NSWorkspace.shared.open(page) }
        default:
            break
        }
    }

    private func info(_ text: String) {
        let alert = NSAlert()
        alert.messageText = appName
        alert.informativeText = text
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - 菜单

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        let about = appMenu.addItem(withTitle: "关于 \(appName)", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(.separator())
        let verItem = NSMenuItem(title: "版本 \(versionString)", action: nil, keyEquivalent: "")
        verItem.isEnabled = false
        appMenu.addItem(verItem)
        let check = appMenu.addItem(withTitle: "检查更新…", action: #selector(checkForUpdatesMenu), keyEquivalent: "")
        check.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return mainMenu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appName,
            .applicationVersion: versionString,
            NSApplication.AboutPanelOptionKey(rawValue: "Version"): versionString,
            .credits: NSAttributedString(
                string: "Mac 显卡信息与监控工具 (支持 AMD 独显与 Apple Silicon)\n数据来自 IOKit，只读；仅在检查更新时访问 GitHub",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
    }
}
