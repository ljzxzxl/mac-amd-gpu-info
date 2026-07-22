import AppKit

/// 信息页：GPU-Z 风格固定版式（每行列数不固定），标签在左、值以输入框样式在右。
/// 支持右键复制、hover 显示完整文本、文本导出，并对外暴露内容高度供窗口自适应。
final class InfoTabViewController: NSViewController {

    struct Cell { let label: String; let value: String }
    enum FormRow { case section(String); case cells([Cell]) }

    var info: GPUInfo? {
        didSet {
            render()
            let hasVBIOS = (info?.vbiosBytes?.isEmpty == false)
            exportVBIOSButton.isEnabled = hasVBIOS
            exportVBIOSButton.toolTip = hasVBIOS
                ? "导出该卡完整 VBIOS 二进制 (.rom)"
                : "该显卡未通过系统公开 VBIOS（Navi/RDNA 显卡在 macOS 上常见），无法读取料号/日期或导出"
        }
    }

    /// 内容实际高度（doc 高度），供 MainWindowController 计算窗口高度。
    private(set) var contentHeight: CGFloat = 0
    /// 标签页内容区所需高度（含滚动区上边距与底部按钮区）。
    var preferredTabContentHeight: CGFloat { contentHeight + 64 }

    private var scroll: NSScrollView!
    private var doc: FlippedView!
    private let exportInfoButton = NSButton(title: "导出信息", target: nil, action: nil)
    private let exportVBIOSButton = NSButton(title: "导出 VBIOS…", target: nil, action: nil)

    // 多卡切换下拉框（置于导出按钮右侧）
    private let gpuPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var gpus: [GPUInfo] = []
    /// 切换显卡回调：由 MainWindowController 注入，用于同步选中源与传感器页。
    var onSelectGPU: ((GPUInfo) -> Void)?


    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 600))

        scroll = NSScrollView(frame: NSRect(x: 12, y: 52, width: 536, height: 536))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .controlBackgroundColor
        scroll.autoresizingMask = [.width, .height]
        doc = FlippedView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 10))
        scroll.documentView = doc
        container.addSubview(scroll)

        exportInfoButton.frame = NSRect(x: 12, y: 12, width: 108, height: 30)
        exportInfoButton.bezelStyle = .rounded
        exportInfoButton.target = self
        exportInfoButton.action = #selector(exportInfo)
        exportInfoButton.autoresizingMask = [.maxYMargin]
        container.addSubview(exportInfoButton)

        exportVBIOSButton.frame = NSRect(x: 126, y: 12, width: 132, height: 30)
        exportVBIOSButton.bezelStyle = .rounded
        exportVBIOSButton.target = self
        exportVBIOSButton.action = #selector(exportVBIOS)
        exportVBIOSButton.autoresizingMask = [.maxYMargin]
        container.addSubview(exportVBIOSButton)

        // 显卡切换下拉框：紧邻“导出 VBIOS…”右侧，占满剩余宽度
        let gpuLab = UI.label("显卡", size: 12, color: .secondaryLabelColor)
        gpuLab.frame = NSRect(x: 266, y: 18, width: 32, height: 16)
        gpuLab.autoresizingMask = [.maxYMargin]
        container.addSubview(gpuLab)
        gpuPopup.frame = NSRect(x: 300, y: 12, width: container.bounds.width - 300 - 12, height: 28)
        gpuPopup.autoresizingMask = [.width, .maxYMargin]
        gpuPopup.target = self
        gpuPopup.action = #selector(gpuChanged)
        container.addSubview(gpuPopup)

        self.view = container
        render()
    }

    // MARK: - 多卡切换

    /// 配置下拉框显卡列表并选中当前卡。仅一张卡时禁用切换。
    func configureGPUs(_ list: [GPUInfo], current: UInt64?) {
        gpus = list
        guard isViewLoaded else { return }
        gpuPopup.removeAllItems()
        if list.isEmpty {
            gpuPopup.addItem(withTitle: "未检测到 AMD 显卡")
            gpuPopup.isEnabled = false
            return
        }
        for g in list {
            // 仅当存在同名型号时才追加 PCI 位置以区分；否则只显示型号。
            let duplicated = list.filter { $0.modelName == g.modelName }.count > 1
            let loc = (duplicated ? g.pciLocation.map { " @\($0)" } : nil) ?? ""
            gpuPopup.addItem(withTitle: "\(g.modelName)\(loc)")
        }
        gpuPopup.isEnabled = list.count > 1
        if let cur = current, let idx = list.firstIndex(where: { $0.registryID == cur }) {
            gpuPopup.selectItem(at: idx)
        }
    }

    @objc private func gpuChanged() {
        let idx = gpuPopup.indexOfSelectedItem
        guard idx >= 0, idx < gpus.count else { return }
        let g = gpus[idx]
        self.info = g
        onSelectGPU?(g)
    }

    // MARK: - 版式定义

    private func buildRows(_ info: GPUInfo) -> [FormRow] {
        func hex(_ v: UInt32?, _ w: Int) -> String { v.map { String(format: "0x%0\(w)X", $0) } ?? "—" }
        func s(_ v: String?) -> String { (v?.isEmpty == false) ? v! : "—" }
        func i(_ v: Int?, _ unit: String = "") -> String { v.map { "\($0)\(unit)" } ?? "未知" }

        var rows: [FormRow] = []
        rows.append(.section("显卡"))
        rows.append(.cells([Cell(label: "型号", value: info.modelName)]))
        rows.append(.cells([
            Cell(label: "芯片", value: s(info.chip)),
            Cell(label: "架构", value: s(info.architecture)),
            Cell(label: "制程", value: s(info.process)),
        ]))
        rows.append(.cells([
            Cell(label: "Device ID", value: hex(info.deviceID, 4)),
            Cell(label: "Vendor ID", value: hex(info.vendorID, 4)),
            Cell(label: "Revision", value: hex(info.revisionID, 2)),
        ]))
        rows.append(.cells([
            Cell(label: "品牌", value: s(info.brand)),
            Cell(label: "总线接口", value: s(info.pcieLink)),
        ]))

        rows.append(.section("规格（型号参考值）"))
        rows.append(.cells([
            Cell(label: "流处理器", value: i(info.shaders)),
            Cell(label: "TMU / ROP", value: info.tmus != nil ? "\(info.tmus!) / \(info.rops ?? 0)" : "未知"),
            Cell(label: "计算单元", value: info.computeUnits.map { "\($0) CU" } ?? "未知"),
        ]))
        rows.append(.cells([
            Cell(label: "额定核心", value: i(info.ratedCoreMHz, " MHz")),
            Cell(label: "额定显存", value: i(info.ratedMemMHz, " MHz")),
            Cell(label: "芯片规模", value: info.dieSizeMM2.map { "\($0)mm² / \(info.transistorsB ?? 0)B" } ?? "未知"),
        ]))

        rows.append(.section("显存"))
        rows.append(.cells([
            Cell(label: "容量", value: info.vramMB.map { "\($0) MB" } ?? "—"),
            Cell(label: "类型", value: s(info.vramType)),
            Cell(label: "颗粒厂商", value: s(info.memoryVendor)),
            Cell(label: "位宽", value: info.busWidthBit.map { "\($0)-bit" } ?? "—"),
        ]))

        rows.append(.section("BIOS"))
        rows.append(.cells([
            Cell(label: "料号", value: s(info.biosPartNumber)),
            Cell(label: "ATOMBIOS", value: s(info.biosVersion)),
        ]))
        rows.append(.cells([
            Cell(label: "构建日期", value: s(info.biosDate)),
            Cell(label: "VBIOS 大小", value: info.vbiosBytes.map { "\($0.count) 字节" } ?? "不可用"),
        ]))
        rows.append(.cells([Cell(label: "板卡标识", value: s(info.biosBoard))]))
        rows.append(.cells([Cell(label: "子系统", value: s(info.subsystemString))]))

        rows.append(.section("软件"))
        rows.append(.cells([Cell(label: "系统", value: s(info.osVersion))]))
        rows.append(.cells([
            Cell(label: "Metal", value: s(info.metalSupport)),
            Cell(label: "驱动", value: s(info.driver)),
        ]))
        return rows
    }

    // MARK: - 渲染

    private func render() {
        guard isViewLoaded, let info = info else { return }
        doc.subviews.forEach { $0.removeFromSuperview() }

        let usable = max(scroll.contentSize.width, 500)
        let leftM: CGFloat = 16, rightM: CGFloat = 14
        let rowW = usable - leftM - rightM
        let labelW: CGFloat = 52
        let boxH: CGFloat = 21
        var y: CGFloat = 12

        for row in buildRows(info) {
            switch row {
            case .section(let title):
                y += 8
                let l = UI.label(title, size: 12, color: .labelColor, bold: true)
                l.frame = NSRect(x: leftM, y: y, width: rowW, height: 18)
                doc.addSubview(l)
                y += 20
                let sep = NSBox(frame: NSRect(x: leftM, y: y, width: rowW, height: 1))
                sep.boxType = .separator
                doc.addSubview(sep)
                y += 8
            case .cells(let cells):
                let cw = rowW / CGFloat(cells.count)
                for (idx, c) in cells.enumerated() {
                    let x = leftM + cw * CGFloat(idx)
                    let lab = UI.label(c.label, size: 11, color: .secondaryLabelColor)
                    lab.frame = NSRect(x: x, y: y + 3, width: labelW, height: 15)
                    doc.addSubview(lab)
                    let box = UI.valueBox(c.value)
                    box.frame = NSRect(x: x + labelW + 2, y: y, width: max(cw - labelW - 10, 44), height: boxH)
                    doc.addSubview(box)
                }
                y += boxH + 7
            }
        }
        contentHeight = y + 12
        doc.frame = NSRect(x: 0, y: 0, width: usable, height: contentHeight)
    }

    // MARK: - 导出

    private func infoText() -> String {
        guard let info = info else { return "" }
        var out = "Mac AMD GPU Info\n"
        for row in buildRows(info) {
            switch row {
            case .section(let t): out += "\n[\(t)]\n"
            case .cells(let cs): for c in cs { out += "  \(c.label): \(c.value)\n" }
            }
        }
        return out
    }

    @objc private func exportInfo() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gpu-info.txt"
        panel.begin { [weak self] result in
            guard let self = self, result == .OK, let url = panel.url else { return }
            try? self.infoText().data(using: .utf8)?.write(to: url)
        }
    }

    @objc private func exportVBIOS() {
        guard let bytes = info?.vbiosBytes, !bytes.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(info?.biosPartNumber ?? "vbios").rom"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            try? bytes.write(to: url)
        }
    }
}
