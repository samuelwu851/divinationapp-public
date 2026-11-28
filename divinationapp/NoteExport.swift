#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// 笔记导出成 PDF。
///
/// 流程：编辑器给出正文 HTML（排盘是 `<div data-chart-id="N">`，图片是 `attachment:文件名`）
/// → 每个排盘换成完整排盘的图片（App 的纸纹背景，分成几段，分页只落在段与段之间）、图片换成内嵌数据
/// → 放进一个看不见的网页里排版 → 走打印存成 A4、白底的 PDF。
///
/// 排盘图片用 SwiftUI 的 ImageRenderer 画：它画不了滚动区、输入框、按钮，
/// 所以导出用的是各排盘的「导出版」视图（见 `ChartExport.sections`），视图里可以读 `\.chartExporting` 把按钮藏掉。
@MainActor
enum NoteExport {
    /// 导出设置（点「导出 PDF」先弹出来让用户选）。
    struct Options {
        var wuxingColor = false
        /// 易经速查、梅花易数要不要写出卦辞爻辞
        var guaText = true
        /// 八字要不要在大运下面列流年（大运一定导出）
        var liunian = true
        /// 记住上次的选择
        static let guaTextKey = "noteExportGuaText"
        static let liunianKey = "noteExportLiunian"

        /// 勾上的选项（传给注册表里的类型）
        var enabled: Set<ChartExportSetting> {
            var s = Set<ChartExportSetting>()
            if guaText { s.insert(.guaText) }
            if liunian { s.insert(.liunian) }
            return s
        }
    }

    /// 正文里这些类型的排盘用得上哪些导出选项（决定设置面板显示什么；空的就不弹设置面板）。
    static func settings(forTypes types: Set<String>) -> Set<ChartExportSetting> {
        var s = Set<ChartExportSetting>()
        for t in types {
            switch t {
            case "iching", "meihua": s.insert(.guaText)
            case "bazi": s.insert(.liunian)
            default: s.formUnion(ChartKindRegistry.kind(for: t)?.exportSettings ?? [])
            }
        }
        return s
    }

    /// 弹保存框，导出成 PDF。失败时弹提示。
    static func run(title: String, bodyHTML: String, options: Options, window: NSWindow?) async {
        let panel = NSSavePanel()
        panel.title = "导出 PDF"
        panel.nameFieldStringValue = (title.isEmpty ? "笔记" : sanitized(title)) + ".pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let html = page(title: title, body: bodyHTML, options: options)
        try? FileManager.default.removeItem(at: url)      // 保存框已经问过要不要替换
        let ok = await PDFPrinter().print(html: html, to: url, window: window)
        if !ok {
            let a = NSAlert()
            a.messageText = "导出失败"
            a.informativeText = "没能生成 PDF。"
            a.alertStyle = .warning
            a.runModal()
        }
    }

    /// 正文里有哪些类型的排盘（如 bazi / iching / meihua / daliuren）。设置面板据此只显示用得上的选项。
    static func chartTypes(inHTML html: String, client: DivinationClient) -> Set<String> {
        struct Head: Decodable { let type: String }
        var types = Set<String>()
        _ = replace(in: html, pattern: #"<div data-chart-id="(\d+)""#) { g in
            if let id = Int(g[1]), let data = client.chartGet(id: id),
               let h = try? JSONDecoder().decode(Head.self, from: data) { types.insert(h.type) }
            return g[0]
        }
        return types
    }

    /// 文件名里不能有的字符换掉。
    private static func sanitized(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "／").replacingOccurrences(of: ":", with: "：")
    }

    // MARK: - 拼网页

    static func page(title: String, body: String, options: Options) -> String {
        let client = DivinationClient()
        var html = replace(in: body, pattern: #"<div data-chart-id="(\d+)"[^>]*>\s*</div>"#) { g in
            chartBlock(id: Int(g[1]) ?? 0, client: client, options: options)
        }
        html = replace(in: html, pattern: #"<img\s[^>]*src="attachment:[^"]*"[^>]*>"#) { g in image(tag: g[0]) }
        let head = title.isEmpty ? "" : "<h1 class=\"note-title\">\(escape(title))</h1>"
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>\(css)</style></head>
        <body>\(head)<div class="body">\(html)</div></body></html>
        """
    }

    /// 一个排盘：图片（按 A4 正文宽专门排的版式，原尺寸放进来），下面是所问之事 + 特点（同笔记里卡片下面那一行）。
    private static func chartBlock(id: Int, client: DivinationClient, options: Options) -> String {
        let data = client.chartGet(id: id)
        let pieces = ChartExport.pieces(ChartDetailView.load(data), data: data, client: client, options: options)
        let imgs = pieces.enumerated().compactMap { i, p in
            ChartExport.png(p, first: i == 0, last: i == pieces.count - 1, wuxingColor: options.wuxingColor).map { png, w in
                // 窄图（如不写卦辞的单卦）：按原尺寸居中；其他铺满正文宽
                "<img class=\"sec\(p.compact ? " solo" : "")\"" + (p.compact ? " style=\"width:\(Int(w.rounded()))px\"" : "") +
                " src=\"data:image/png;base64,\(png.base64EncodedString())\">"
            }
        }.joined()
        if imgs.isEmpty { return "<div class=\"chart-missing\">（这个排盘已被删除或无法显示）</div>" }
        var below = ""
        if let meta = ChartDetailView.loadMeta(data) {
            if !meta.title.isEmpty { below += "<div class=\"cc-question\">\(escape(meta.title))</div>" }
            let tags = meta.tags ?? []
            if !tags.isEmpty {
                below += "<div class=\"cc-tags\">" + tags.map { "<span class=\"cc-tag\">\(escape($0.name))</span>" }.joined() + "</div>"
            }
        }
        return "<div class=\"chart\">\(imgs)</div>" + (below.isEmpty ? "" : "<div class=\"chart-below\">\(below)</div>")
    }

    /// 正文里的一张图片：内嵌数据；对齐、大小同编辑器——按记下的宽度（旧笔记的百分比按 480 宽换算，没记就 480），
    /// 但不超过图片本身的像素宽度（小图不放大，免得糊），也不超过纸宽。
    private static func image(tag: String) -> String {
        func attr(_ name: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: "\\b\(name)=\"([^\"]*)\""),
                  let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) else { return nil }
            return unescape((tag as NSString).substring(with: m.range(at: 1)))
        }
        guard let src = attr("src"), src.hasPrefix("attachment:"),
              let dir = CasebookPaths.attachmentsDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(String(src.dropFirst("attachment:".count)))) else {
            return ""
        }
        let name = String(src.dropFirst("attachment:".count))
        let mime = UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType ?? "image/png"
        let refWidth: Double = 480                                   // 同编辑器 IMG_REF_WIDTH
        var width = refWidth
        if let w = attr("width"), let n = Double(w.trimmingCharacters(in: CharacterSet(charactersIn: "px% "))) {
            width = w.hasSuffix("%") ? n / 100 * refWidth : n
        }
        var maxW = "100%"
        if let src = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let px = props[kCGImagePropertyPixelWidth] as? Int {
            maxW = "min(100%, \(px)px)"
        }
        let align = attr("data-align") ?? "left"            // 对齐同编辑器里的设置
        return "<img src=\"data:\(mime);base64,\(data.base64EncodedString())\" data-align=\"\(escape(align))\" " +
            "style=\"width:\(Int(width.rounded()))px;max-width:\(maxW)\">"
    }

    // MARK: - 小工具

    /// 正则替换，替换内容由每次匹配的分组算出来（g[0] 整段，g[1]… 分组）。
    private static func replace(in s: String, pattern: String, _ make: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let groups = (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
            out += make(groups)
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// 和编辑器正文的样式一致（字号按纸张缩小一些），背景纯白。
    private static let css = """
    :root { --fg: #1d1d1f; --secondary: rgba(60,60,67,0.6); --fill: rgba(120,120,128,0.12); --stroke: rgba(60,60,67,0.18);
      --c-red: #c62828; --c-orange: #e65100; --c-yellow: #a07800; --c-green: #2e7d32;
      --c-blue: #1565c0; --c-purple: #6a1b9a; --c-gray: #757575; --hl: #fff3a0; }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; background: #fff; color: var(--fg);
      font: 14px/1.65 -apple-system, BlinkMacSystemFont, "PingFang SC", "PingFang TC", sans-serif;
      -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .note-title { font-size: 24px; line-height: 1.3; margin: 0 0 12px; }
    .body { word-wrap: break-word; white-space: pre-wrap; }
    .body > * + * { margin-top: 0.45em; }
    .body p { margin: 0; }
    .body h1 { font-size: 23px; margin: 0.6em 0 0.2em; line-height: 1.3; }
    .body h2 { font-size: 19px; margin: 0.6em 0 0.2em; line-height: 1.35; }
    .body h3 { font-size: 16px; margin: 0.5em 0 0.2em; line-height: 1.4; }
    .body ul, .body ol { padding-left: 1.4em; margin: 0.2em 0; }
    .body li > p { margin: 0; }
    .body blockquote { margin: 0.4em 0; padding-left: 12px; border-left: 3px solid var(--stroke); color: var(--secondary); }
    .body hr { border: 0; border-top: 1px solid var(--stroke); margin: 1em 0; }
    .body code { background: var(--fill); border-radius: 4px; padding: 0 4px; font-size: 0.9em; }
    .c-red { color: var(--c-red); } .c-orange { color: var(--c-orange); } .c-yellow { color: var(--c-yellow); }
    .c-green { color: var(--c-green); } .c-blue { color: var(--c-blue); } .c-purple { color: var(--c-purple); }
    .c-gray { color: var(--c-gray); }
    mark { background: var(--hl); color: inherit; border-radius: 2px; padding: 0 1px; }
    table { border-collapse: collapse; table-layout: fixed; width: 100%; margin: 0.4em 0; }
    td, th { border: 1px solid var(--stroke); padding: 4px 8px; vertical-align: top; }
    th { background: var(--fill); font-weight: 600; text-align: left; }
    td p, th p { margin: 0; }
    .body img { display: block; height: auto; border-radius: 6px; break-inside: avoid; }
    .body img[data-align="center"] { margin-left: auto; margin-right: auto; }
    .body img[data-align="right"] { margin-left: auto; margin-right: 0; }
    .chart { margin: 6px 0 0; white-space: normal; }
    .chart img.sec { display: block; width: 100%; height: auto; border-radius: 0;
      break-inside: avoid; page-break-inside: avoid; }
    .chart img.sec:first-child { border-top-left-radius: 8px; border-top-right-radius: 8px; }
    .chart img.sec:last-child { border-bottom-left-radius: 8px; border-bottom-right-radius: 8px; }
    .chart img.sec.solo { margin: 0 auto; border-radius: 8px; }
    .chart-below { white-space: normal; break-before: avoid; page-break-before: avoid; }
    .cc-question { margin-top: 6px; padding: 0 4px; font-size: 13px; line-height: 1.45; }
    .cc-tags { margin-top: 4px; padding: 0 4px; display: flex; flex-wrap: wrap; gap: 4px; }
    .cc-tag { font-size: 11px; padding: 1px 8px; border-radius: 999px; background: var(--fill); }
    .chart-missing { color: var(--secondary); font-size: 13px; }
    """
}

// MARK: - 排盘图片

/// 导出时为 true：排盘视图里的按钮（如六壬的设置齿轮）读它藏起来。
private struct ChartExportingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var chartExporting: Bool {
        get { self[ChartExportingKey.self] }
        set { self[ChartExportingKey.self] = newValue }
    }
}

@MainActor
enum ChartExport {
    /// A4 正文宽（pt）：595 − 左右各 42 的页边。排盘图片按这个宽度排版，放进 PDF 时就是原尺寸（不缩放）。
    static let pageWidth: CGFloat = 511
    /// 画图的倍数：3 倍，打印放大也清楚。
    static let renderScale: CGFloat = 3

    /// 一盘拆成几段（每段一张图，上下紧贴；分页只会落在段与段之间）。
    /// 一段图片。compact：按内容本身的宽度画（背景不撑满），放进 PDF 时居中。
    struct Piece {
        let view: AnyView
        var compact = false
    }

    /// data：chart_get 的原始 JSON（注册表里的类型自己解码）。
    static func pieces(_ loaded: ChartDetailView.Loaded, data: Data?, client: DivinationClient, options: NoteExport.Options) -> [Piece] {
        var compact = false
        if case .iching(_, let org, let chg, _, _) = loaded, org.lines == chg.lines, !options.guaText { compact = true }
        return raw(loaded, data: data, client: client, options: options).map { Piece(view: $0, compact: compact) }
    }

    private static func raw(_ loaded: ChartDetailView.Loaded, data: Data?, client: DivinationClient, options: NoteExport.Options) -> [AnyView] {
        let guaText = options.guaText
        switch loaded {
        case .bazi(let chart, let name, let birth):
            // 两段：上面四柱，下面大运（+ 流年）。分页可以落在两段之间
            return [AnyView(BaziChartView(chart: chart, name: name, birth: birth, exportPart: .pillars)),
                    AnyView(VStack(spacing: 8) {
                        Divider()
                        BaziChartView(chart: chart, name: name, birth: birth, exportPart: .dayun(liunian: options.liunian))
                    })]
        case .iching(_, let org, let chg, let yilin, let cangua):
            let cg = cangua ?? client.cangua(org: org.value, chg: chg.value)
            let view = AnyView(GuaExportView(title: "易经速查", org: org, chg: chg, yilin: yilin, cangua: cg, showText: guaText))
            return [view] + (guaText ? dualGuaTextPieces(org, chg, cg) : [])
        case .meihua(let bazi, let methodText, let org, let chg, let yilin, let cangua):
            let cg = cangua ?? client.cangua(org: org.value, chg: chg.value)
            return [AnyView(GuaExportView(title: "梅花易数", bazi: bazi, methodText: methodText, org: org, chg: chg,
                                          yilin: yilin, cangua: cg, showText: guaText))]
                + (guaText ? dualGuaTextPieces(org, chg, cg) : [])
        case .registered(let kind, let view):
            if let data, let pieces = kind.makeExport?(data, options.enabled) { return pieces }
            return [view]                    // 没有专门的导出版式：视图自己读 \.chartExporting 换版式（如六壬）
        case .unsupported, .missing:
            return []
        }
    }

    /// 一段画成 PNG：纸纹背景、浅色模式、五行颜色跟着详情窗口的勾选。返回 (PNG, 宽度 pt)。
    /// 第一段上面、最后一段下面留得多一点，中间的段上下少留，拼起来像一整张。
    static func png(_ piece: Piece, first: Bool, last: Bool, wuxingColor: Bool) -> (Data, CGFloat)? {
        let padded = piece.view
            .padding(.horizontal, piece.compact ? 24 : 14)
            .padding(.top, first ? 12 : 4)
            .padding(.bottom, last ? 12 : 4)
        let sized = piece.compact
            ? AnyView(padded.fixedSize())
            : AnyView(padded.frame(width: pageWidth))
        let content = sized
            .background(PatternBackground())
            .environment(\.colorScheme, .light)
            .environment(\.wuxingColorOn, wuxingColor)
            .environment(\.chartExporting, true)
        let r = ImageRenderer(content: content)
        r.scale = renderScale
        r.proposedSize = piece.compact ? .unspecified : ProposedViewSize(width: pageWidth, height: nil)
        guard let cg = r.cgImage,
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return nil }
        return (data, CGFloat(cg.width) / renderScale)
    }
}

/// 易经速查 / 梅花易数的导出版式（A4 正文宽，高约 1/4–1/3 页）。不写卦辞爻辞。
/// 左边本卦、变卦（中间动爻标 →）；右边一格一个小卦：第一行本卦的错综互，第二行变卦的错综互，第三行参卦。
private struct GuaExportView: View {
    let title: String
    var bazi: BaziPillarsResult? = nil
    var methodText: String? = nil
    let org: Hexagram
    let chg: Hexagram
    let yilin: String?
    let cangua: [CanGuaGroup]
    /// 单卦时右边写不写卦辞爻辞（导出设置）
    var showText = true
    @Environment(\.wuxingColorOn) private var colorOn

    private var moving: Set<Int> {
        Set((0..<min(org.lines.count, chg.lines.count)).filter { org.lines[$0] != chg.lines[$0] })
    }

    var body: some View {
        let dual = !moving.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let bazi {
                    BaziPillarsView(pillars: bazi.ganzhis, charFont: .system(size: 13))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bazi.inputTime)
                        Text(bazi.lunarTime)
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                } else if let methodText {
                    Text(methodText).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if dual {
                HStack(alignment: .center, spacing: 0) {
                    HStack(alignment: .top, spacing: 6) {
                        bigGua(org.name, org.lines, org.trigrams, org.palace)
                        arrows
                        bigGua(chg.name, chg.lines, chg.trigrams, chg.palace)
                    }
                    .fixedSize()
                    Spacer(minLength: 16)
                    Grid(alignment: .top, horizontalSpacing: 6, verticalSpacing: 8) {
                        GridRow {
                            rowLabel("本卦")
                            ForEach(org.derived) { mini($0.name, $0.label, $0.lines, $0.trigrams) }
                        }
                        GridRow {
                            rowLabel("变卦")
                            ForEach(chg.derived) { mini($0.name, $0.label, $0.lines, $0.trigrams) }
                        }
                        if !cangua.isEmpty {
                            GridRow {
                                rowLabel("参卦")
                                ForEach(cangua) { g in
                                    ForEach(g.guas, id: \.label) { c in
                                        mini(c.derived.name, "\(g.partName)\(c.label)", c.derived.lines, c.derived.trigrams)
                                    }
                                }
                            }
                        }
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                }
            } else {
                // 单卦：左边本卦、下面错综互（同详情窗口）；右边两栏写卦辞爻辞
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 14) {
                        bigGua(org.name, org.lines, org.trigrams, org.palace)
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(org.derived) { mini($0.name, $0.label, $0.lines, $0.trigrams) }
                        }
                    }
                    .fixedSize()
                    if showText {
                        GuaTextGrid(items: GuaText.collect(org, chg, cangua), columns: 2)
                    }
                }
            }
            if let yilin, dual {
                Text("易林：\(yilin)").font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // 大卦：卦名、六爻（宽 84、高 11）、八宫
    private func bigGua(_ name: String, _ lines: [Int], _ tri: Trigrams?, _ palace: Palace?) -> some View {
        VStack(spacing: 6) {
            Text(name).font(.system(size: 15, weight: .bold))
            VStack(spacing: 5) {
                ForEach((0..<lines.count).reversed(), id: \.self) { i in
                    yao(lines[i] == 1, width: 84, height: 11, gap: 8, wuxing: colorOn ? yaoWuxing(i, tri, lines: lines) : nil)
                }
            }
            if let palace { Text(palace.text).font(.system(size: 9)).foregroundStyle(.secondary) }
        }
        .frame(width: 92)
    }

    /// 本卦和变卦中间一列：动爻那一行画 →，和大卦的爻对齐。
    private var arrows: some View {
        VStack(spacing: 5) {
            ForEach((0..<org.lines.count).reversed(), id: \.self) { i in
                Text(moving.contains(i) ? "→" : " ").font(.system(size: 10)).frame(height: 11)
            }
        }
        .padding(.top, 6 + 18)          // 让过卦名那一行
    }

    // 小卦：卦名、六爻（宽 34、高 4）、身份
    private func mini(_ name: String, _ label: String, _ lines: [Int], _ tri: Trigrams?) -> some View {
        VStack(spacing: 3) {
            Text(name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            VStack(spacing: 2.5) {
                ForEach((0..<lines.count).reversed(), id: \.self) { i in
                    yao(lines[i] == 1, width: 34, height: 4, gap: 4, wuxing: colorOn ? yaoWuxing(i, tri, lines: lines) : nil)
                }
            }
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 50)
    }

    private func rowLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 9)).foregroundStyle(.secondary)
            .fixedSize()                       // 不让旁边的空白把这一列挤没了
            .frame(height: 50)                 // 大致在小卦中间
    }

    private func yao(_ yang: Bool, width: CGFloat, height: CGFloat, gap: CGFloat, wuxing: String?) -> some View {
        HStack(spacing: gap) {
            if yang {
                YaoBar(width: width, height: height, radius: height / 4, wuxing: wuxing)
            } else {
                YaoBar(width: (width - gap) / 2, height: height, radius: height / 4, wuxing: wuxing)
                YaoBar(width: (width - gap) / 2, height: height, radius: height / 4, wuxing: wuxing)
            }
        }
        .frame(width: width)
    }
}

/// 易经类的卦辞爻辞：图里出现的每个卦一段。同一个卦出现几次只写一次，身份并在一起（如「本卦错卦 · 本卦综卦」）。
/// 注册表里的类型（如别的术数）也可以用：`collect(_:)` 收卦，`ChartExport.guaTextPieces(_:)` 排成图。
struct GuaText: Identifiable {
    var roles: [String]
    let name: String
    let palace: Palace?
    let lines: [Int]
    let text: HexagramText
    var id: String { name }

    /// 按顺序收一串卦，每个卦连同它的错综互（身份写成「会卦错卦」这样）。重复的卦只留第一次，身份并进去。
    static func collect(_ items: [(role: String, hexagram: Hexagram)]) -> [GuaText] {
        var out: [GuaText] = []
        for (role, h) in items {
            add(&out, role, h.name, h.palace, h.lines, h.hexagramText)
            for d in h.derived { add(&out, "\(role)\(d.label)", d.name, d.palace, d.lines, d.text) }
        }
        return out
    }

    private static func add(_ out: inout [GuaText], _ role: String, _ name: String, _ palace: Palace?, _ lines: [Int], _ text: HexagramText) {
        if let i = out.firstIndex(where: { $0.name == name }) { out[i].roles.append(role) }
        else { out.append(GuaText(roles: [role], name: name, palace: palace, lines: lines, text: text)) }
    }

    static func collect(_ org: Hexagram, _ chg: Hexagram, _ cangua: [CanGuaGroup]) -> [GuaText] {
        var out: [GuaText] = []
        func add(_ role: String, _ name: String, _ palace: Palace?, _ lines: [Int], _ text: HexagramText) {
            Self.add(&out, role, name, palace, lines, text)
        }
        let dual = org.lines != chg.lines
        add("本卦", org.name, org.palace, org.lines, org.hexagramText)
        if dual { add("变卦", chg.name, chg.palace, chg.lines, chg.hexagramText) }
        for d in org.derived { add(dual ? "本卦\(d.label)" : d.label, d.name, d.palace, d.lines, d.text) }
        if dual {
            for d in chg.derived { add("变卦\(d.label)", d.name, d.palace, d.lines, d.text) }
            for g in cangua {
                for c in g.guas { add("\(g.partName)\(c.label)", c.derived.name, c.derived.palace, c.derived.lines, c.derived.text) }
            }
        }
        return out
    }
}

/// 一个卦的卦辞爻辞（A4 用的小字）。
private struct GuaTextBlock: View {
    let g: GuaText
    var body: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(g.name).font(.system(size: 11, weight: .bold))
                Text(g.roles.joined(separator: " · ")).font(.system(size: 8)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let p = g.palace { Text(p.text).font(.system(size: 8)).foregroundStyle(.secondary) }
            }
            .padding(.bottom, 1)
            hanging("卦辞", g.text.still)
            ForEach(0..<g.text.lines.count, id: \.self) { i in
                if i < 6, i < g.lines.count {
                    hanging(yaoTitle(index: i, isYang: g.lines[i] == 1), g.text.lines[i])
                } else {
                    Text(g.text.lines[i])                      // 用九 / 用六
                }
            }
        }
        .font(.system(size: 9.5))
        .lineSpacing(1.5)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 爻题 + 爻辞：折行时第二行和爻辞对齐（悬挂缩进），不顶到爻题下面。
    private func hanging(_ head: String, _ body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(head).frame(width: 22, alignment: .leading)
            Text(body).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 卦辞爻辞排成几栏（一行放 columns 个卦）。
private struct GuaTextGrid: View {
    let items: [GuaText]
    var columns = 2
    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 10) {
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + columns, items.count), id: \.self) { GuaTextBlock(g: items[$0]) }
                    if start + columns > items.count {
                        ForEach(0..<(start + columns - items.count), id: \.self) { _ in Color.clear.frame(height: 0) }
                    }
                }
            }
        }
    }
}

/// 有动爻时卦图下面的卦辞爻辞：一行两个卦，每行一段图片（分页落在行与行之间）。
@MainActor
private func dualGuaTextPieces(_ org: Hexagram, _ chg: Hexagram, _ cangua: [CanGuaGroup]) -> [AnyView] {
    guard org.lines != chg.lines else { return [] }       // 单卦的卦辞爻辞在卦图右边
    return ChartExport.guaTextPieces(GuaText.collect(org, chg, cangua))
}

extension ChartExport {
    /// 卦辞爻辞排成图：一行两个卦，每行一段（分页落在行与行之间），第一段上面有分隔线和上面的图隔开。
    static func guaTextPieces(_ items: [GuaText]) -> [AnyView] {
        stride(from: 0, to: items.count, by: 2).map { start in
            let row = Array(items[start..<min(start + 2, items.count)])
            return AnyView(VStack(spacing: 8) {
                if start == 0 { Divider() }                     // 和卦图隔开
                GuaTextGrid(items: row, columns: 2)
            }.padding(.top, start == 0 ? 0 : 4))
        }
    }
}

// MARK: - 打印成 PDF

/// 把一段 HTML 放进看不见的网页里，走打印存成 PDF（A4，自动分页）。
@MainActor
private final class PDFPrinter: NSObject, WKNavigationDelegate {
    private var loaded: CheckedContinuation<Bool, Never>?
    private var printed: CheckedContinuation<Bool, Never>?
    private var webView: WKWebView?

    // A4：595 × 842 pt；四边留约 15mm
    private static let paper = NSSize(width: 595.28, height: 841.89)
    private static let margin: CGFloat = 42

    func print(html: String, to url: URL, window: NSWindow?) async -> Bool {
        let w = WKWebView(frame: NSRect(x: 0, y: 0, width: Self.paper.width - 2 * Self.margin, height: Self.paper.height))
        w.navigationDelegate = self
        webView = w
        let ok = await withCheckedContinuation { c in
            loaded = c
            w.loadHTMLString(html, baseURL: nil)
        }
        guard ok else { return false }

        let info = NSPrintInfo()
        info.paperSize = Self.paper
        info.topMargin = Self.margin; info.bottomMargin = Self.margin
        info.leftMargin = Self.margin; info.rightMargin = Self.margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let op = w.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.view?.frame = w.bounds
        guard let window else { return op.run() && FileManager.default.fileExists(atPath: url.path) }
        let done = await withCheckedContinuation { c in
            printed = c
            op.runModal(for: window, delegate: self, didRun: #selector(printDone(_:success:contextInfo:)), contextInfo: nil)
        }
        webView = nil
        return done && FileManager.default.fileExists(atPath: url.path)
    }

    @objc private func printDone(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        printed?.resume(returning: success)
        printed = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume(returning: true); loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(returning: false); loaded = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(returning: false); loaded = nil
    }
}
#endif
