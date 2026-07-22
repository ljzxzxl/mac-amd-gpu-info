import AppKit

/// 简易折线图：两条 0–100 归一化曲线（温度、GPU 活跃度），环形缓冲。
final class SensorGraphView: NSView {

    private let capacity = 120
    private var temp: [Double] = []
    private var activity: [Double] = []

    private let tempColor = NSColor.systemRed
    private let actColor = NSColor.systemBlue

    func append(temp t: Double?, activity a: Double?) {
        push(&temp, t)
        push(&activity, a)
        needsDisplay = true
    }

    private func push(_ arr: inout [Double], _ v: Double?) {
        arr.append(max(0, min(100, v ?? 0)))
        if arr.count > capacity { arr.removeFirst(arr.count - capacity) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let inset: CGFloat = 4
        let plot = bounds.insetBy(dx: inset, dy: inset)

        // 网格线（0/25/50/75/100）
        NSColor.gridColor.setStroke()
        for f in stride(from: 0.0, through: 1.0, by: 0.25) {
            let y = plot.minY + plot.height * CGFloat(f)
            let p = NSBezierPath()
            p.move(to: NSPoint(x: plot.minX, y: y))
            p.line(to: NSPoint(x: plot.maxX, y: y))
            p.lineWidth = 0.5
            p.stroke()
        }

        drawSeries(temp, color: tempColor, in: plot)
        drawSeries(activity, color: actColor, in: plot)

        // 图例
        let legend = NSMutableAttributedString()
        legend.append(NSAttributedString(string: "■ 温度  ", attributes: [.foregroundColor: tempColor, .font: NSFont.systemFont(ofSize: 10)]))
        legend.append(NSAttributedString(string: "■ GPU 活跃度", attributes: [.foregroundColor: actColor, .font: NSFont.systemFont(ofSize: 10)]))
        legend.draw(at: NSPoint(x: plot.minX + 4, y: plot.maxY - 14))
    }

    private func drawSeries(_ data: [Double], color: NSColor, in plot: NSRect) {
        guard data.count > 1 else { return }
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        let stepX = plot.width / CGFloat(capacity - 1)
        for (i, v) in data.enumerated() {
            let x = plot.minX + stepX * CGFloat(i)
            let y = plot.minY + plot.height * CGFloat(v / 100.0)
            let pt = NSPoint(x: x, y: y)
            if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
        }
        path.stroke()
    }
}
