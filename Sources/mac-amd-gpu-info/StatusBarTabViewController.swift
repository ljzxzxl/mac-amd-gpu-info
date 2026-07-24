import AppKit

/// 「状态栏」标签页：主开关 + 8 指标开关（两列）+ 开机自启动开关。
final class StatusBarTabViewController: NSViewController {

    private let settings = StatusBarSettings.shared
    private var masterSwitch: NSButton!
    private var autostartSwitch: NSButton!
    private var gpuPopup: NSPopUpButton?
    private var metricSwitches: [NSButton] = []       // 顺序对应 StatusBarMetric.allCases
    private var dependentControls: [NSControl] = []   // 主开关关闭时置灰

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 600))
        let doc = FlippedView(frame: container.bounds)
        doc.autoresizingMask = [.width, .height]
        container.addSubview(doc)

        let leftM: CGFloat = 24
        var y: CGFloat = 24

        masterSwitch = NSButton(checkboxWithTitle: "在状态栏显示实时监控", target: self, action: #selector(toggleMaster))
        masterSwitch.font = .boldSystemFont(ofSize: 13)
        masterSwitch.frame = NSRect(x: leftM, y: y, width: 460, height: 22)
        doc.addSubview(masterSwitch)
        y += 42

        let hint = UI.label("显示以下指标（并排紧凑显示在状态栏）：", size: 12, color: .secondaryLabelColor)
        hint.frame = NSRect(x: leftM, y: y, width: 460, height: 16)
        doc.addSubview(hint)
        y += 26

        let col0X = leftM + 16
        let col1X = leftM + 240
        for (i, m) in StatusBarMetric.allCases.enumerated() {
            let cb = NSButton(checkboxWithTitle: m.title, target: self, action: #selector(toggleMetric(_:)))
            cb.tag = i
            let row = i / 2, col = i % 2
            cb.frame = NSRect(x: col == 0 ? col0X : col1X, y: y + CGFloat(row) * 28, width: 210, height: 20)
            metricSwitches.append(cb)
            dependentControls.append(cb)
            doc.addSubview(cb)
        }
        y += CGFloat((StatusBarMetric.allCases.count + 1) / 2) * 28 + 24

        // 多显卡时：选择状态栏显示哪张卡的传感器
        let gpus = GPUSelection.shared.gpus
        if gpus.count >= 2 {
            let glabel = UI.label("状态栏显示：", size: 12, color: .secondaryLabelColor)
            glabel.frame = NSRect(x: leftM, y: y + 4, width: 90, height: 16)
            doc.addSubview(glabel)

            let popup = NSPopUpButton(frame: NSRect(x: leftM + 90, y: y - 1, width: 380, height: 26))
            popup.target = self
            popup.action = #selector(changeGPU(_:))
            popup.addItem(withTitle: "跟随主界面选择")
            for g in gpus { popup.addItem(withTitle: g.modelName) }
            if let rid = settings.gpuRegistryID, let idx = gpus.firstIndex(where: { $0.registryID == rid }) {
                popup.selectItem(at: idx + 1)
            } else {
                popup.selectItem(at: 0)
            }
            doc.addSubview(popup)
            gpuPopup = popup
            dependentControls.append(popup)
            y += 40
        }

        autostartSwitch = NSButton(checkboxWithTitle: "状态栏随开机自动启动（登录后进入纯状态栏模式）",
                                   target: self, action: #selector(toggleAutostart))
        autostartSwitch.frame = NSRect(x: leftM, y: y, width: 500, height: 22)
        dependentControls.append(autostartSwitch)
        doc.addSubview(autostartSwitch)
        y += 40

        let note = UI.label("提示：关闭主窗口后，只要状态栏开启，应用会在后台驻留；\n可从状态栏图标菜单重新打开主窗口。",
                            size: 11, color: .tertiaryLabelColor)
        note.frame = NSRect(x: leftM, y: y, width: 500, height: 34)
        (note.cell as? NSTextFieldCell)?.wraps = true
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 2
        doc.addSubview(note)

        self.view = container
        syncFromSettings()
    }

    private func syncFromSettings() {
        masterSwitch.state = settings.enabled ? .on : .off
        for (i, m) in StatusBarMetric.allCases.enumerated() {
            metricSwitches[i].state = settings.isMetricOn(m) ? .on : .off
        }
        autostartSwitch.state = LoginItem.isEnabled ? .on : .off
        updateEnabledState()
    }

    private func updateEnabledState() {
        let on = settings.enabled
        dependentControls.forEach { $0.isEnabled = on }
    }

    @objc private func toggleMaster() {
        settings.enabled = (masterSwitch.state == .on)
        updateEnabledState()
    }

    @objc private func toggleMetric(_ sender: NSButton) {
        let m = StatusBarMetric.allCases[sender.tag]
        settings.setMetric(m, sender.state == .on)
    }

    @objc private func changeGPU(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        let gpus = GPUSelection.shared.gpus
        if idx <= 0 {
            settings.gpuRegistryID = nil            // 跟随主界面
        } else if idx - 1 < gpus.count {
            settings.gpuRegistryID = gpus[idx - 1].registryID
        }
    }

    @objc private func toggleAutostart() {
        let want = (autostartSwitch.state == .on)
        if LoginItem.set(want) {
            settings.autostart = want
        } else {
            autostartSwitch.state = LoginItem.isEnabled ? .on : .off   // 回滚
        }
    }
}
