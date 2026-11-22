import SwiftUI

/// 纯线条「笔记本」图标（现画，非 SF/emoji）。24×24 设计坐标，按 frame 自适应缩放。
struct NotebookIcon: View {
    var color: Color = .primary
    var lineWidth: CGFloat = 1.6

    var body: some View {
        Canvas { ctx, size in
            let u = min(size.width, size.height) / 24     // 单位：设计坐标 → 实际
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }

            // 封面/书页外框
            let cover = Path(roundedRect: CGRect(x: 5 * u, y: 3 * u, width: 15 * u, height: 18 * u),
                             cornerRadius: 2 * u)
            ctx.stroke(cover, with: .color(color), lineWidth: lineWidth)

            // 书脊竖线
            var spine = Path(); spine.move(to: P(9, 3)); spine.addLine(to: P(9, 21))
            ctx.stroke(spine, with: .color(color), lineWidth: lineWidth)

            // 书脊上的装订小横线（线圈感）
            for y in stride(from: 5.5, through: 18.5, by: 2.6) {
                var tick = Path(); tick.move(to: P(6.5, y)); tick.addLine(to: P(9, y))
                ctx.stroke(tick, with: .color(color), lineWidth: lineWidth * 0.8)
            }

            // 页面上的文字线
            for y in [8.0, 12.0, 16.0] as [CGFloat] {
                var line = Path(); line.move(to: P(11.5, y)); line.addLine(to: P(17.5, y))
                ctx.stroke(line, with: .color(color), lineWidth: lineWidth * 0.9)
            }
        }
    }
}

/// 纯线条「笔（铅笔）」图标（现画）。24×24 设计坐标。斜向左下，笔尖在左下。
struct PenIcon: View {
    var color: Color = .primary
    var lineWidth: CGFloat = 1.8

    var body: some View {
        Canvas { ctx, size in
            let u = min(size.width, size.height) / 24
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }

            // 笔身外轮廓：顶端(橡皮端) → 上棱 → 笔尖 → 下棱 → 回顶端
            var body = Path()
            body.move(to: P(15, 6))      // 顶端左
            body.addLine(to: P(7, 14))   // 上棱到近尖
            body.addLine(to: P(5.5, 18.5)) // 笔尖
            body.addLine(to: P(10, 17))  // 下棱回来
            body.addLine(to: P(18, 9))   // 下棱到顶端右
            body.closeSubpath()          // 顶端封口
            ctx.stroke(body, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))

            // 笔尖处的「笔箍」横线
            var collar = Path(); collar.move(to: P(7, 14)); collar.addLine(to: P(10, 17))
            ctx.stroke(collar, with: .color(color), lineWidth: lineWidth * 0.9)
        }
    }
}
