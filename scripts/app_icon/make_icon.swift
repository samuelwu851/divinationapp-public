// 第二步：用描好的轮廓画 App 图标（白底用五行「金」的灰白，黑字），输出 16–1024 各尺寸。
// 用法：swiftc -O -o /tmp/icon scripts/app_icon/make_icon.swift && /tmp/icon scripts/app_icon/yi_contours.txt divinationapp/Assets.xcassets/AppIcon.appiconset

import AppKit
import CoreGraphics

// App 图标：甲骨文「易」。字形照用户给的参考图描成矢量（轮廓见 yi_contours.txt：
// 参考图坐标，每行一个闭合轮廓），白底黑字；白底用五行「金」的灰白 #EEEBE5，边框 #ACA89F（同 GuaWuXingColor）。
let contourText = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let loops: [[CGPoint]] = contourText.split(separator: "\n").map { line in
    line.split(separator: " ").map { pair in
        let v = pair.split(separator: ",").map { Double($0)! }
        return CGPoint(x: v[0], y: v[1])
    }
}
let all = loops.flatMap { $0 }
let minX = all.map(\.x).min()!, maxX = all.map(\.x).max()!
let minY = all.map(\.y).min()!, maxY = all.map(\.y).max()!

func draw(_ ctx: CGContext, _ size: CGFloat) {
    let s = size / 1024
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: 0, y: 1024); ctx.scaleBy(x: 1, y: -1)        // 左上角为原点

    // 底：macOS 圆角方块（824 见方，圆角 185），五行金的灰白 + 细灰边，下面一点阴影
    let plate = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.25))
    ctx.addPath(plate); ctx.setFillColor(CGColor(red: 0xEE/255, green: 0xEB/255, blue: 0xE5/255, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(plate); ctx.setStrokeColor(CGColor(red: 0xAC/255, green: 0xA8/255, blue: 0x9F/255, alpha: 1)); ctx.setLineWidth(5); ctx.strokePath()

    // 字：等比缩放到高 600，放在正中
    let gh = maxY - minY, gw = maxX - minX
    let k = 600 / gh
    let ox = 512 - gw * k / 2 - minX * k, oy = 512 - gh * k / 2 - minY * k
    let path = CGMutablePath()
    for l in loops {
        path.addLines(between: l.map { CGPoint(x: ox + $0.x * k, y: oy + $0.y * k) })
        path.closeSubpath()
    }
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 0.11, green: 0.10, blue: 0.10, alpha: 1))
    ctx.fillPath(using: .evenOdd)          // 三角里面那个洞
}

func png(_ px: Int, _ path: String) {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx, CGFloat(px))
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}
let out = CommandLine.arguments[2]
for px in [16, 32, 64, 128, 256, 512, 1024] { png(px, "\(out)/icon_\(px).png") }
