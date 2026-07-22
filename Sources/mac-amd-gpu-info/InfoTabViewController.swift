import AppKit

/// 信息页：以对齐的「字段: 值」列表展示静态信息，底部提供 VBIOS 导出。
final class InfoTabViewController: NSViewController {

    var info: GPUInfo? { didSet { render() } }

    private let textView = NSTextView()
    private let exportButton = NSButton(title: "导出 VBIOS…", target: nil, action: nil)

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 552))

        let scroll = NSScrollView(frame: NSRect(x: 12, y: 52, width: 516, height: 488))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autoresizingMask = [.width, .height]

        textView.isEditable = false
        textView.isRichText = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        container.addSubview(scroll)

        exportButton.frame = NSRect(x: 12, y: 12, width: 150, height: 30)
        exportButton.bezelStyle = .rounded
        exportButton.target = self
        exportButton.action = #selector(exportVBIOS)
        exportButton.autoresizingMask = [.minYMargin]
        container.addSubview(exportButton)

        self.view = container
        render()
    }

    private func render() {
        guard isViewLoaded, let info = info else { return }
        exportButton.isEnabled = (info.vbiosBytes?.isEmpty == false)

        let body = NSMutableAttributedString()
        func section(_ title: String) {
            body.append(NSAttributedString(string: "\n\(title)\n", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        func row(_ label: String, _ value: String?, note: String? = nil) {
            let padded = label.padding(toLength: 12, withPad: " ", startingAt: 0)
            let v = (value?.isEmpty == false ? value! : "—")
            let line = "  \(padded)  \(v)\(note.map { "  (\($0))" } ?? "")\n"
            body.append(NSAttributedString(string: line, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]))
        }
        func hex(_ v: UInt32?, width: Int) -> String? {
            v.map { String(format: "0x%0\(width)X", $0) }
        }

        section("基本")
        row("型号", info.modelName)
        row("品牌", info.brand, note: info.brand == nil ? nil : "VBIOS")
        row("芯片", info.chip, note: info.chip == nil ? nil : "型号规格")
        row("架构", info.architecture)
        row("制程", info.process)
        row("Device ID", hex(info.deviceID, width: 4))
        row("Vendor ID", hex(info.vendorID, width: 4))
        row("Revision", hex(info.revisionID, width: 2))
        row("总线接口", info.pcieLink)

        section("规格（型号参考值）")
        row("流处理器", info.shaders.map(String.init))
        row("TMU / ROP", info.tmus != nil ? "\(info.tmus!) / \(info.rops ?? 0)" : nil)
        row("计算单元", info.computeUnits.map { "\($0) CU" })
        row("额定频率", info.ratedCoreMHz.map { "核心 \($0) MHz / 显存 \(info.ratedMemMHz ?? 0) MHz" })
        row("die / 晶体管", info.dieSizeMM2.map { "\($0) mm² / \(info.transistorsB ?? 0) B" })

        section("显存")
        row("容量", info.vramMB.map { "\($0) MB" })
        row("类型", info.vramType)
        row("颗粒厂商", info.memoryVendor)
        row("位宽", info.busWidthBit.map { "\($0)-bit" })

        section("BIOS")
        row("料号", info.biosPartNumber)
        row("ATOMBIOS", info.biosVersion)
        row("构建日期", info.biosDate)
        row("板卡标识", info.biosBoard)
        row("子系统", info.subsystemString)
        row("VBIOS", info.vbiosBytes.map { "\($0.count) 字节" })

        section("软件")
        row("系统", info.osVersion)
        row("Metal", info.metalSupport)
        row("驱动", info.driver)

        textView.textStorage?.setAttributedString(body)
    }

    @objc private func exportVBIOS() {
        guard let bytes = info?.vbiosBytes, !bytes.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(info?.biosPartNumber ?? "vbios").rom"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try bytes.write(to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "导出失败"
                alert.informativeText = error.localizedDescription
                alert.runModal()
                _ = self
            }
        }
    }
}
