import SwiftUI
import Charts
import MirissaCore

struct TrendChart: View {
    var points: [TrendPoint]
    var title: String

    private struct Row: Identifiable {
        var id: String { "\(month)-\(series)" }
        var month: String
        var order: Int
        var series: String
        var value: Double
    }

    private var rows: [Row] {
        points.enumerated().flatMap { i, p -> [Row] in
            let label = Dates.displayMonthShort(p.month)
            return [
                Row(month: label, order: i, series: "Gelir", value: Money.toTL(p.gelir)),
                Row(month: label, order: i, series: "Gider", value: Money.toTL(p.gider)),
                Row(month: label, order: i, series: "Kâr", value: Money.toTL(p.kar)),
            ]
        }
    }

    private var isEmpty: Bool {
        points.allSatisfy { $0.gelir == 0 && $0.gider == 0 && $0.kar == 0 }
    }

    private var labels: [String] { points.map { Dates.displayMonthShort($0.month) } }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(title.trUpper)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.inkFaint)

                if isEmpty {
                    EmptyHint(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Henüz veri yok",
                        message: "Satış ve gider girdikçe aylık gidişat burada görünecek."
                    )
                } else {
                    Chart(rows) { r in
                        LineMark(
                            x: .value("Ay", r.month),
                            y: .value("TL", r.value)
                        )
                        .foregroundStyle(by: .value("Seri", r.series))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .symbol {
                            Circle().frame(width: 5, height: 5)
                        }
                        .interpolationMethod(.monotone)
                    }
                    .chartForegroundStyleScale([
                        "Gelir": Palette.kar,
                        "Gider": Palette.gider,
                        "Kâr": Palette.uyari,
                    ])
                    .chartXScale(domain: labels)
                    .chartLegend(position: .bottom, spacing: 10)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Palette.separator)
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(shortTL(v))
                                        .font(.caption2)
                                        .foregroundStyle(Palette.inkFaint)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.caption2)
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    private func shortTL(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if a >= 1000 { return "\(Int(v / 1000))B" }
        return "\(Int(v))"
    }
}
