import SwiftUI

/// 八字排盘输入页。两种方式：
/// - 按时间：填姓名/性别/出生时间（公历或农历，公元 1–2200 年）→「开始排盘」进入新页面出全盘；
///   农历先请后端换成公历，再走 bazi_chart。
/// - 按八字反推：选年月日时四柱的干支 →「查找时间」列出公元 1–2200 年里对得上的时刻 → 点一个排盘。
struct BaziView: View {
    @State private var name = ""
    @State private var isMale = true

    // 出生时间（公历 / 农历）
    @State private var date = DateInputModel(years: HistoricalCalendar.baziYears, initial: .now())
    @State private var birth: Birth?                   // 排盘用的公历时刻（农历已换算）

    @State private var chart: BaziChart?
    @State private var showChart = false
    @State private var errorMessage: String?

    // 按八字反推
    @State private var byPillars = false

    private let client = DivinationClient()


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Text("八字排盘").font(.largeTitle).bold()

                    // 姓名 + 性别 同一行
                    HStack(spacing: 16) {
                        Text("姓名").font(.title3)
                        TextField("请输入姓名", text: $name)
                            .textFieldStyle(.plain)
                            .font(.title3)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
                            .frame(width: 200)

                        Picker("", selection: $isMale) {
                            Text("男").tag(true)
                            Text("女").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 130)
                    }

                    Picker("", selection: $byPillars) {
                        Text("按时间排盘").tag(false)
                        Text("按八字反推").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    .onChange(of: byPillars) { _, _ in errorMessage = nil }

                    if byPillars {
                        PillarsReverseInput(client: client) { runChart($0) }   // 点一个时刻就排盘
                    } else {
                        // 出生时间：公历 / 农历（公元 1–2200 年），滚轮字号调大便于老年用户；年份也可以直接输入
                        CalendarModeSwitch(model: date)
                        DateInputWheels(model: date)

                        Button { paipan() } label: {
                            Text("开始排盘").font(.headline)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 28)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.callout)
                    }


                }
                .padding(40)
                .frame(maxWidth: .infinity)
            }
            .navigationDestination(isPresented: $showChart) {
                if let chart, let birth {
                    BaziChartView(chart: chart, name: name, birth: birth)
                }
            }
        }
    }

    // MARK: - 按时间排盘

    private func paipan() {
        guard let s = date.resolvedSolar() else {
            errorMessage = "农历日期换算失败（超出公元 1–2200 年？）"; return
        }
        runChart(s)
    }

    private func runChart(_ s: DateParts) {
        guard let c = client.baziChart(year: s.year, month: s.month, day: s.day,
                                       hour: s.hour, minute: s.minute, isMale: isMale) else {
            errorMessage = "排盘失败：日期不存在或超出范围"; return
        }
        errorMessage = nil
        birth = Birth(year: s.year, month: s.month, day: s.day, hour: s.hour, minute: s.minute)
        chart = c
        showChart = true
    }
}

/// 八字反推的一个结果：这个时辰里四柱都对得上的起止时刻，pick 是拿去排盘的那一刻。
struct ReverseMatch: Decodable, Identifiable {
    struct Parts: Decodable { let year, month, day, hour, minute: Int }
    let start: String
    let end: String
    let lunar: String
    let pickParts: Parts
    var id: String { start }
}

struct ReverseResult: Decodable {
    let results: [ReverseMatch]
}

/// 出生公历时刻（排流月时要带着命主生辰再问后端）。
struct Birth: Hashable {
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
}
