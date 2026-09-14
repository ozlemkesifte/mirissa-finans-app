import SwiftUI
import MirissaCore

enum ReportTab: String, CaseIterable, Identifiable {
    case aylik, yillik, kanallar
    var id: String { rawValue }
    var label: String {
        switch self {
        case .aylik: return "Aylık"
        case .yillik: return "Yıllık"
        case .kanallar: return "Kanallar"
        }
    }
}

struct ReportsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    @State private var tab: ReportTab = .aylik
    @State private var sheet: AppSheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    Picker("", selection: $tab) {
                        ForEach(ReportTab.allCases) { t in Text(t.label).tag(t) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch tab {
                    case .aylik: MonthlyReport()
                    case .yillik: YearlyReport()
                    case .kanallar: ChannelReport(onEdit: { id in sheet = .channelMonth(id, period.month) })
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.top, 4)
            }
            .screenBackground()
            .navigationTitle("Raporlar")
            .largeTitleMode()
            .appSheets($sheet)
        }
    }
}

// MARK: - Aylık

struct MonthlyReport: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period

    private var result: CompanyMonthResult { store.engine.companyMonth(period.month) }

    var body: some View {
        VStack(spacing: Metrics.gap) {
            MonthStepper(month: Bindable(period).month)
            ResultSummary(
                title: Dates.displayMonth(period.month),
                ciro: result.gercekCiro,
                gider: result.toplamGider,
                kar: result.gercekKar,
                marj: result.karMarjiPct
            )
            ExpenseBreakdownCard(breakdown: result.expenseBreakdown, total: result.toplamGider)
            if result.units > 0 {
                Card {
                    VStack(spacing: 9) {
                        LabeledRow("Satılan ürün", "\(Int(result.units)) adet")
                        if result.orders > 0 { LabeledRow("Sipariş", "\(result.orders)") }
                        if result.units > 0 {
                            LabeledRow("Ürün başına kalan",
                                       Money.roundHalfAwayFromZero(Double(result.gercekKar) / result.units).tl,
                                       tone: result.gercekKar < 0 ? Palette.zarar : Palette.kar)
                        }
                        if result.stokAlimi != 0 {
                            LabeledRow("Stok alımı (nakit)", result.stokAlimi.tl, tone: Palette.inkSoft)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Yıllık

struct YearlyReport: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    @State private var openMonth: MonthKey?

    private var year: Int { period.year }
    private var result: YearResult { store.engine.year(year) }

    var body: some View {
        VStack(spacing: Metrics.gap) {
            HStack {
                Button { period.month = Dates.addMonths(period.month, -12) } label: {
                    Image(systemName: "chevron.left").font(.subheadline.weight(.bold))
                }
                .buttonStyle(.plain).foregroundStyle(Palette.accent)
                Spacer()
                Text("\(year)").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Button { period.month = Dates.addMonths(period.month, 12) } label: {
                    Image(systemName: "chevron.right").font(.subheadline.weight(.bold))
                }
                .buttonStyle(.plain).foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.vertical, 12)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

            ResultSummary(
                title: "\(year) Toplamı",
                ciro: result.gercekCiro,
                gider: result.toplamGider,
                kar: result.gercekKar,
                marj: result.karMarjiPct
            )

            TrendChart(points: result.trend, title: "Ocak – Aralık")

            SectionTitle("Aylar")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(result.months.enumerated()), id: \.element.id) { i, m in
                        MonthRowView(result: m, open: openMonth == m.month) {
                            withAnimation(.snappy(duration: 0.2)) {
                                openMonth = openMonth == m.month ? nil : m.month
                            }
                        }
                        if i < result.months.count - 1 {
                            Divider().overlay(Palette.separator).padding(.leading, Metrics.pad)
                        }
                    }
                }
            }

            ExpenseBreakdownCard(breakdown: result.expenseBreakdown, total: result.toplamGider)
        }
    }
}

private struct MonthRowView: View {
    var result: CompanyMonthResult
    var open: Bool
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack {
                    Text(Dates.displayMonth(result.month))
                        .font(.subheadline)
                        .foregroundStyle(result.hasData ? Palette.ink : Palette.inkFaint)
                    Spacer(minLength: 8)
                    Text(result.gercekKar.tlCompact)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(result.gercekKar < 0 ? Palette.zarar
                                         : (result.hasData ? Palette.kar : Palette.inkFaint))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 8) {
                    LabeledRow("Gerçek ciro", result.gercekCiro.tl)
                    LabeledRow("Toplam gider", result.toplamGider.tl)
                    LabeledRow("Kâr marjı", Money.formatPercent(result.karMarjiPct))
                    ForEach(result.channels.filter { !$0.isEmpty }) { c in
                        LabeledRow(c.channelName, c.kanaldaKalan.tl,
                                   tone: c.kanaldaKalan < 0 ? Palette.zarar : Palette.kar)
                    }
                }
                .padding(.horizontal, Metrics.pad)
                .padding(.bottom, 14)
            }
        }
    }
}

// MARK: - Kanallar

struct ChannelReport: View {
    @Environment(AppStore.self) private var store
    @Environment(Period.self) private var period
    var onEdit: (Id) -> Void

    var body: some View {
        VStack(spacing: Metrics.gap) {
            PeriodPicker(period: period)
            ForEach(store.state.activeChannels) { ch in
                let r = store.engine.channelTotals(from: period.from, to: period.to, channelId: ch.id)
                Card {
                    VStack(spacing: 10) {
                        HStack {
                            Text(ch.name.trUpper)
                                .font(.caption.weight(.semibold))
                                .tracking(0.6)
                                .foregroundStyle(Palette.inkFaint)
                            Spacer()
                            if r.netSales > 0 {
                                Pill(Money.formatPercent(r.marginPct),
                                     tone: r.kanaldaKalan < 0 ? Palette.zarar : Palette.kar,
                                     background: r.kanaldaKalan < 0 ? Palette.zararYumusak : Palette.karYumusak)
                            }
                        }
                        Divider().overlay(Palette.separator)
                        LabeledRow("Toplam satış", r.grossSales.tl)
                        if r.discount != 0 { LabeledRow("İndirim", "-" + r.discount.tl) }
                        if r.returnsAmount != 0 { LabeledRow("İade", "-" + r.returnsAmount.tl) }
                        LabeledRow("Net satış", r.netSales.tl, strong: true)
                        LabeledRow("Satılan ürün", "\(Int(r.units)) adet")
                        if r.commission.amount != 0 { LabeledRow("Komisyon", "-" + r.commission.amount.tl) }
                        if r.shipping.amount != 0 { LabeledRow("Kargo", "-" + r.shipping.amount.tl) }
                        if r.serviceFee.amount != 0 { LabeledRow("Hizmet bedeli", "-" + r.serviceFee.amount.tl) }
                        if r.otherDeduction.amount != 0 { LabeledRow("Diğer kesinti", "-" + r.otherDeduction.amount.tl) }
                        if r.ads.amount != 0 { LabeledRow("Reklam", "-" + r.ads.amount.tl) }
                        if r.productCost != 0 { LabeledRow("Ürün maliyeti", "-" + r.productCost.tl) }
                        if r.packagingCost != 0 { LabeledRow("Ambalaj", "-" + r.packagingCost.tl) }
                        Divider().overlay(Palette.separator)
                        LabeledRow("KANALDA KALAN", r.kanaldaKalan.tl,
                                   tone: r.kanaldaKalan < 0 ? Palette.zarar : Palette.kar, strong: true)
                        if period.scope == .month {
                            Button { onEdit(ch.id) } label: {
                                Label("Gerçek kesintileri gir", systemImage: "pencil")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Palette.inset)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.accent)
                        }
                    }
                }
            }
            Card(background: Palette.inset) {
                Text("Kanalda kalan, şirket net kârı değildir. Ortak şirket giderleri ayrıca bu tutardan düşülür.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            }
        }
    }
}

// MARK: - Ortak parçalar

struct MonthStepper: View {
    @Binding var month: MonthKey

    var body: some View {
        HStack {
            Button { month = Dates.addMonths(month, -1) } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.bold))
            }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
            Spacer()
            Text(Dates.displayMonth(month)).font(.headline).foregroundStyle(Palette.ink)
            Spacer()
            Button { month = Dates.addMonths(month, 1) } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.bold))
            }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
        }
        .padding(.horizontal, Metrics.pad)
        .padding(.vertical, 12)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

struct ResultSummary: View {
    var title: String
    var ciro: Kurus
    var gider: Kurus
    var kar: Kurus
    var marj: Double

    var body: some View {
        Card {
            VStack(spacing: 11) {
                Text(title.trUpper)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LabeledRow("Gerçek ciro", ciro.tl)
                LabeledRow("Toplam gider", gider.tl, tone: Palette.gider)
                Divider().overlay(Palette.separator)
                HStack(alignment: .firstTextBaseline) {
                    Text(kar < 0 ? "GERÇEK ZARAR" : "GERÇEK KÂR")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(kar.tl)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(kar < 0 ? Palette.zarar : Palette.kar)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                LabeledRow("Kâr marjı", Money.formatPercent(marj),
                           tone: kar < 0 ? Palette.zarar : Palette.kar)
            }
        }
    }
}

struct ExpenseBreakdownCard: View {
    var breakdown: [ExpenseCategory: Kurus]
    var total: Kurus

    private var rows: [(ExpenseCategory, Kurus)] {
        breakdown.filter { $0.value != 0 }.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(spacing: Metrics.gap) {
            SectionTitle("Gider Dağılımı")
            Card {
                if rows.isEmpty {
                    Text("Bu dönemde gider yok.")
                        .font(.footnote).foregroundStyle(Palette.inkFaint)
                } else {
                    VStack(spacing: 12) {
                        ForEach(rows, id: \.0) { cat, amount in
                            VStack(spacing: 5) {
                                HStack {
                                    Text(cat.displayName).font(.subheadline).foregroundStyle(Palette.inkSoft)
                                    Spacer()
                                    Text(amount.tl).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Palette.inset)
                                        Capsule().fill(Palette.gider.opacity(0.75))
                                            .frame(width: geo.size.width * share(amount))
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                    }
                }
            }
        }
    }

    private func share(_ a: Kurus) -> CGFloat {
        total > 0 ? min(max(CGFloat(a) / CGFloat(total), 0), 1) : 0
    }
}
