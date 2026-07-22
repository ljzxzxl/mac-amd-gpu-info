import AppKit

/// 可右键复制的文本控件；hover 显示完整内容（toolTip）。
final class CopyableLabel: NSTextField {
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        let item = NSMenuItem(title: "复制", action: #selector(copyValue), keyEquivalent: "")
        item.target = self
        m.addItem(item)
        return m
    }
    @objc private func copyValue() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(stringValue, forType: .string)
    }
}

/// 顶部对齐的翻转容器，便于从上往下手动排版。
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 统一的控件工厂：项目标签 + 输入框样式的值框。
enum UI {
    static func label(_ text: String, size: CGFloat, color: NSColor, bold: Bool = false) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        f.textColor = color
        f.lineBreakMode = .byTruncatingTail
        f.cell?.usesSingleLineMode = true
        f.isSelectable = true                // 与“值”一致：selectable 才会触发好看的即时展开气泡
        f.allowsExpansionToolTips = true     // 截断时 hover 弹出完整文本
        f.toolTip = text
        return f
    }

    static func valueBox(_ text: String) -> CopyableLabel {
        let f = CopyableLabel()
        f.stringValue = text
        f.font = .systemFont(ofSize: 12)
        f.textColor = .labelColor
        f.isEditable = false
        f.isSelectable = true
        f.isBezeled = true
        f.bezelStyle = .squareBezel
        f.drawsBackground = true
        f.backgroundColor = .textBackgroundColor
        f.lineBreakMode = .byTruncatingTail
        f.cell?.usesSingleLineMode = true
        f.cell?.isScrollable = true
        f.allowsExpansionToolTips = true     // 截断时 hover 弹出完整值气泡
        f.toolTip = text
        return f
    }
}
