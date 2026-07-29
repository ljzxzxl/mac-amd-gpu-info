import AppKit

/// 单张折线图配置里的一条曲线。
struct GraphSeries {
    let label: String
    let color: NSColor
    let maxValue: Double
    let unit: String
}

/// 通用折线图：顶部独立图例带（含当前值，不与曲线重叠），曲线带半透明填充，左侧刻度。
final class SensorGraphView: NSView {

    private let capacity = 120
    private var configs: [GraphSeries] = []
    private var buffers: [[Double]] = []

    /// 该曲线的含义备注，显示在图例右侧，并作为 hover 提示。
    var note: String = "" {
        didSet { toolTip = note; needsDisplay = true }
    }

    private let headerH: CGFloat = 16
    private let leftPad: CGFloat = 34
    private let pad: CGFloat = 5

    // 文本样式为不变量，提到静态常量避免 1Hz 重绘时反复构造字体与字典。
    private static let legendAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]
    private static let noteAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9),
        .foregroundColor: NSColor.tertiaryLabelColor,
    ]
    private static let tickAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 8),
        .foregroundColor: NSColor.tertiaryLabelColor,
    ]

    func configure(_ series: [GraphSeries]) {
        configs = series
        buffers = series.map { _ in [] }
        needsDisplay = true
    }

    func push(_ values: [Double?]) {
        for (i, v) in values.enumerated() where i < buffers.count {
            buffers[i].append(max(0, v ?? 0))
            if buffers[i].count > capacity { buffers[i].removeFirst(buffers[i].count - capacity) }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        drawLegend()

        let plot = NSRect(x: bounds.minX + leftPad, y: bounds.minY + pad,
                          width: bounds.width - leftPad - pad,
                          height: bounds.height - headerH - pad * 2)
        guard plot.width > 0, plot.height > 0 else { return }

        drawGrid(plot)
        for (i, cfg) in configs.enumerated() { drawSeries(buffers[i], cfg: cfg, in: plot) }
    }

    private func drawLegend() {
        let y = bounds.maxY - headerH + 1
        var x = bounds.minX + leftPad
        for (i, cfg) in configs.enumerated() {
            cfg.color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y + 2, width: 9, height: 9), xRadius: 2, yRadius: 2).fill()
            let latest = buffers[i].last
            let text = latest.map { "\(cfg.label) \(Int($0)) \(cfg.unit)" } ?? cfg.label
            let s = NSAttributedString(string: text, attributes: Self.legendAttrs)
            s.draw(at: NSPoint(x: x + 13, y: y))
            x += 13 + s.size().width + 16
        }

        // 右侧含义备注
        if !note.isEmpty {
            let n = NSAttributedString(string: note, attributes: Self.noteAttrs)
            let nx = bounds.maxX - n.size().width - 6
            if nx > x { n.draw(at: NSPoint(x: nx, y: y + 1)) }
        }
    }

    private func drawGrid(_ plot: NSRect) {
        for f in stride(from: 0.0, through: 1.0, by: 0.5) {
            let yy = plot.minY + plot.height * CGFloat(f)
            NSColor.gridColor.withAlphaComponent(0.5).setStroke()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: plot.minX, y: yy))
            p.line(to: NSPoint(x: plot.maxX, y: yy))
            p.lineWidth = 0.5
            p.stroke()
        }
        if let maxV = configs.first?.maxValue {
            for f in [0.0, 0.5, 1.0] {
                let yy = plot.minY + plot.height * CGFloat(f)
                NSAttributedString(string: "\(Int(maxV * f))", attributes: Self.tickAttrs)
                    .draw(at: NSPoint(x: bounds.minX + 3, y: yy - 5))
            }
        }
    }

    private func drawSeries(_ data: [Double], cfg: GraphSeries, in plot: NSRect) {
        guard data.count > 1, cfg.maxValue > 0 else { return }
        let stepX = plot.width / CGFloat(capacity - 1)
        func pt(_ i: Int, _ v: Double) -> NSPoint {
            NSPoint(x: plot.minX + stepX * CGFloat(i),
                    y: plot.minY + plot.height * CGFloat(min(1.0, v / cfg.maxValue)))
        }

        let fill = NSBezierPath()
        fill.move(to: NSPoint(x: pt(0, data[0]).x, y: plot.minY))
        for (i, v) in data.enumerated() { fill.line(to: pt(i, v)) }
        fill.line(to: NSPoint(x: pt(data.count - 1, data[data.count - 1]).x, y: plot.minY))
        fill.close()
        cfg.color.withAlphaComponent(0.12).setFill()
        fill.fill()

        let line = NSBezierPath()
        line.lineWidth = 1.5
        line.lineJoinStyle = .round
        for (i, v) in data.enumerated() {
            let p = pt(i, v)
            if i == 0 { line.move(to: p) } else { line.line(to: p) }
        }
        cfg.color.setStroke()
        line.stroke()
    }
}
