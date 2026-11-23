// 第一步：把参考图（甲骨文「易」的位图）描成平滑的矢量轮廓。
// 用法：swiftc -O -o /tmp/trace scripts/app_icon/trace.swift && /tmp/trace 参考图.png scripts/app_icon/yi_contours.txt 1.4
// 最后一个参数是先做的高斯模糊（像素）：越大边缘越平滑，尖角也越圆。

import AppKit
import CoreGraphics

// 把参考图里的字描成矢量：
// 1. 每个像素算「多黑」（0 = 白，1 = 黑），抗锯齿的灰边也算进去
// 2. 在 0.5 这条等高线上走 marching squares：边界点按灰度线性插值，落在像素之间（亚像素），不是一格一格的锯齿
// 3. 再用 Chaikin 细分把折线磨圆
// 4. 得到一组闭合轮廓（字的外边 + 三角里面那个洞），用 even-odd 填充
let img = NSImage(contentsOfFile: CommandLine.arguments[1])!
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let W = rep.pixelsWide, H = rep.pixelsHigh
var f = [[Double]](repeating: [Double](repeating: 0, count: W + 2), count: H + 2)   // 四周补一圈白
for y in 0..<H { for x in 0..<W {
    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    f[y + 1][x + 1] = 1 - Double(c.redComponent + c.greenComponent + c.blueComponent) / 3
}}
// 先轻轻模糊一下（高斯 σ≈1 像素）：去掉原图边缘一格一格的噪点，不改变笔画走向
let sigma = Double(CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "1.0")!
let rad = Int(ceil(sigma * 3))
let kern = (-rad...rad).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
let ksum = kern.reduce(0, +)
func blur(_ g: [[Double]], horizontal: Bool) -> [[Double]] {
    var o = g
    for y in 0..<g.count { for x in 0..<g[0].count {
        var acc = 0.0
        for (i, w) in kern.enumerated() {
            let d = i - rad
            let yy = horizontal ? y : min(max(y + d, 0), g.count - 1)
            let xx = horizontal ? min(max(x + d, 0), g[0].count - 1) : x
            acc += g[yy][xx] * w
        }
        o[y][x] = acc / ksum
    }}
    return o
}
f = blur(blur(f, horizontal: true), horizontal: false)
let level = 0.5
struct P: Hashable { let x: Double; let y: Double }
func key(_ p: P) -> String { String(format: "%.4f,%.4f", p.x, p.y) }

var segs: [(P, P)] = []
func lerp(_ a: Double, _ b: Double) -> Double { (level - a) / (b - a) }
for y in 0..<(H + 1) { for x in 0..<(W + 1) {
    let tl = f[y][x], tr = f[y][x+1], br = f[y+1][x+1], bl = f[y+1][x]
    let idx = (tl > level ? 8 : 0) | (tr > level ? 4 : 0) | (br > level ? 2 : 0) | (bl > level ? 1 : 0)
    let X = Double(x), Y = Double(y)
    let top = P(x: X + lerp(tl, tr), y: Y), right = P(x: X + 1, y: Y + lerp(tr, br))
    let bottom = P(x: X + lerp(bl, br), y: Y + 1), left = P(x: X, y: Y + lerp(tl, bl))
    switch idx {
    case 1, 14: segs.append((left, bottom))
    case 2, 13: segs.append((bottom, right))
    case 3, 12: segs.append((left, right))
    case 4, 11: segs.append((top, right))
    case 6, 9: segs.append((top, bottom))
    case 7, 8: segs.append((left, top))
    case 5: segs.append((left, top)); segs.append((bottom, right))
    case 10: segs.append((top, right)); segs.append((left, bottom))
    default: break
    }
}}
// 线段连成闭合轮廓
var adj: [String: [P]] = [:]
for (a, b) in segs { adj[key(a), default: []].append(b); adj[key(b), default: []].append(a) }
var used = Set<String>()
func ekey(_ a: P, _ b: P) -> String { let ka = key(a), kb = key(b); return ka < kb ? ka + "|" + kb : kb + "|" + ka }
var loops: [[P]] = []
for (a, b) in segs where !used.contains(ekey(a, b)) {
    var loop = [a, b]; used.insert(ekey(a, b))
    var cur = b, prev = a
    while true {
        guard let next = adj[key(cur)]?.first(where: { !used.contains(ekey(cur, $0)) && key($0) != key(prev) || (!used.contains(ekey(cur, $0)) && adj[key(cur)]!.count == 1) }) else { break }
        used.insert(ekey(cur, next))
        if key(next) == key(loop[0]) { break }
        loop.append(next); prev = cur; cur = next
    }
    if loop.count > 8 { loops.append(loop) }
}
// Chaikin 磨圆（闭合）
func chaikin(_ pts: [P], _ n: Int) -> [P] {
    var p = pts
    for _ in 0..<n {
        var q: [P] = []
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            q.append(P(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y))
            q.append(P(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y))
        }
        p = q
    }
    return p
}
// 沿轮廓等距重采样（每 0.25 像素一个点），再沿走向做高斯平滑（σ≈1.2 像素），最后 Chaikin 收尾
func resample(_ pts: [P], step: Double) -> [P] {
    var out: [P] = [pts[0]]
    var carry = 0.0
    for i in 0..<pts.count {
        let a = pts[i], b = pts[(i + 1) % pts.count]
        let len = hypot(b.x - a.x, b.y - a.y)
        var t = step - carry
        while t <= len {
            out.append(P(x: a.x + (b.x - a.x) * t / len, y: a.y + (b.y - a.y) * t / len))
            t += step
        }
        carry = len - (t - step)
    }
    return out
}
func gaussSmooth(_ pts: [P], sigmaPts: Double) -> [P] {
    let r = Int(ceil(sigmaPts * 3))
    let w = (-r...r).map { exp(-Double($0 * $0) / (2 * sigmaPts * sigmaPts)) }
    let ws = w.reduce(0, +)
    let n = pts.count
    return (0..<n).map { i in
        var x = 0.0, y = 0.0
        for (j, wj) in w.enumerated() { let p = pts[((i + j - r) % n + n) % n]; x += p.x * wj; y += p.y * wj }
        return P(x: x / ws, y: y / ws)
    }
}
let smooth = loops.map { chaikin(gaussSmooth(resample($0, step: 0.25), sigmaPts: 2.6 / 0.25), 1) }
// 输出：轮廓（参考图坐标），每行一个轮廓 "x,y x,y ..."
var out = ""
for l in smooth { out += l.map { String(format: "%.3f,%.3f", $0.x, $0.y) }.joined(separator: " ") + "\n" }
try! out.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
print("loops", smooth.count, smooth.map { $0.count })
